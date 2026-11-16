// Échantillonneur de fils (Astro Bot PC) : suspend périodiquement les fils choisis d'un processus, relit leur pile
// (StackWalk64 + PDB) et compte les fonctions : temps propre (feuille) et inclusif (présente dans la pile).
// Usage : echantillonneur.exe <pid> <nom de fil, sous-chaîne>[,<autre>] <secondes> [intervalle_ms=1] [sortie.txt]
// Compilation : clang-cl /O2 /EHsc echantillonneur.cpp dbghelp.lib  (voir build.cmd)
#include <windows.h>
#include <dbghelp.h>
#include <tlhelp32.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

struct Cible {
	DWORD        tid;
	HANDLE       h;
	std::wstring nom;
};

static std::wstring NomDuFil(HANDLE h) {
	PWSTR d = nullptr;
	std::wstring r;
	if (SUCCEEDED(GetThreadDescription(h, &d)) && d != nullptr) {
		r = d;
		LocalFree(d);
	}
	return r;
}

static std::vector<std::wstring> Separer(const std::wstring& s) {
	std::vector<std::wstring> r;
	size_t                    a = 0;
	while (a <= s.size()) {
		const auto b = s.find(L',', a);
		r.push_back(s.substr(a, b == std::wstring::npos ? std::wstring::npos : b - a));
		if (b == std::wstring::npos) break;
		a = b + 1;
	}
	return r;
}

int wmain(int argc, wchar_t** argv) {
	if (argc < 4) {
		std::fwprintf(stderr, L"usage : echantillonneur <pid> <fils> <secondes> [intervalle_ms] [sortie]\n");
		return 2;
	}
	const DWORD  pid      = static_cast<DWORD>(_wtoi(argv[1]));
	const auto   noms     = Separer(argv[2]);
	const double secondes = _wtof(argv[3]);
	const int    pas_ms   = argc > 4 ? _wtoi(argv[4]) : 1;
	FILE*        out      = stdout;
	if (argc > 5) {
		out = _wfopen(argv[5], L"w, ccs=UTF-8");
		if (out == nullptr) return 3;
	}

	HANDLE proc = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
	if (proc == nullptr) {
		std::fwprintf(stderr, L"OpenProcess %lu : erreur %lu\n", pid, GetLastError());
		return 4;
	}
	SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_FAIL_CRITICAL_ERRORS);
	if (!SymInitializeW(proc, nullptr, TRUE)) {
		std::fwprintf(stderr, L"SymInitialize : erreur %lu\n", GetLastError());
		return 5;
	}

	std::vector<Cible> cibles;
	HANDLE             snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
	THREADENTRY32      te {sizeof(te)};
	for (BOOL ok = Thread32First(snap, &te); ok; ok = Thread32Next(snap, &te)) {
		if (te.th32OwnerProcessID != pid) continue;
		HANDLE h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_LIMITED_INFORMATION, FALSE,
		                      te.th32ThreadID);
		if (h == nullptr) continue;
		const auto nom = NomDuFil(h);
		bool       garde = false;
		for (const auto& n: noms) {
			if (n == L"*") garde = true; // tous les fils, y compris sans nom (13/11 : fils internes de FSR 3)
			if (!n.empty() && nom.find(n) != std::wstring::npos) garde = true;
		}
		if (garde) {
			cibles.push_back({te.th32ThreadID, h, nom});
		} else {
			CloseHandle(h);
		}
	}
	CloseHandle(snap);
	if (cibles.empty()) {
		std::fwprintf(stderr, L"aucun fil ne correspond\n");
		return 6;
	}

	struct Compte {
		uint64_t propre = 0, inclusif = 0;
	};
	std::unordered_map<DWORD64, Compte>     par_adresse_feuille;
	std::unordered_map<std::string, Compte> par_fonction;
	std::unordered_map<DWORD64, std::string> cache_noms;
	std::unordered_map<std::string, uint64_t> appelants; // "appelant <- feuille" (2 niveaux)
	std::unordered_map<std::string, uint64_t> piles;     // piles de 10 niveaux
	std::unordered_map<DWORD64, uint64_t>     lignes_feuille; // adresse exacte de la feuille
	uint64_t                                  echantillons = 0, echecs = 0;

	auto Nom = [&](DWORD64 a) -> const std::string& {
		auto it = cache_noms.find(a);
		if (it != cache_noms.end()) return it->second;
		alignas(SYMBOL_INFO) char buf[sizeof(SYMBOL_INFO) + 1024] {};
		auto*                     si = reinterpret_cast<SYMBOL_INFO*>(buf);
		si->SizeOfStruct            = sizeof(SYMBOL_INFO);
		si->MaxNameLen              = 1023;
		DWORD64     dep             = 0;
		std::string n;
		if (SymFromAddr(proc, a, &dep, si)) {
			n = si->Name;
		} else {
			IMAGEHLP_MODULE64 m {sizeof(m)};
			char              t[64];
			if (SymGetModuleInfo64(proc, a, &m)) {
				std::snprintf(t, sizeof(t), "+0x%llx", static_cast<unsigned long long>(a - m.BaseOfImage));
				n = std::string(m.ModuleName) + t;
			} else {
				std::snprintf(t, sizeof(t), "?0x%llx", static_cast<unsigned long long>(a));
				n = t;
			}
		}
		return cache_noms.emplace(a, std::move(n)).first->second;
	};

	const auto fin = std::chrono::steady_clock::now() + std::chrono::milliseconds(static_cast<int64_t>(secondes * 1000));
	timeBeginPeriod(1);
	std::vector<DWORD64> pile;
	while (std::chrono::steady_clock::now() < fin) {
		for (auto& c: cibles) {
			if (SuspendThread(c.h) == static_cast<DWORD>(-1)) continue;
			CONTEXT ctx {};
			ctx.ContextFlags = CONTEXT_FULL;
			pile.clear();
			if (GetThreadContext(c.h, &ctx)) {
				STACKFRAME64 f {};
				f.AddrPC.Offset    = ctx.Rip;
				f.AddrPC.Mode      = AddrModeFlat;
				f.AddrFrame.Offset = ctx.Rbp;
				f.AddrFrame.Mode   = AddrModeFlat;
				f.AddrStack.Offset = ctx.Rsp;
				f.AddrStack.Mode   = AddrModeFlat;
				for (int i = 0; i < 96; i++) {
					if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, proc, c.h, &f, &ctx, nullptr, SymFunctionTableAccess64,
					                 SymGetModuleBase64, nullptr) ||
					    f.AddrPC.Offset == 0)
						break;
					pile.push_back(f.AddrPC.Offset);
				}
			}
			ResumeThread(c.h);
			if (pile.empty()) {
				echecs++;
				continue;
			}
			echantillons++;
			// Noms résolus hors suspension (les appels dbghelp sont lents).
			lignes_feuille[pile[0]]++;
			std::unordered_set<std::string> vus;
			for (size_t i = 0; i < pile.size(); i++) {
				const auto& n = Nom(i == 0 ? pile[i] : pile[i] - 1);
				if (i == 0) par_fonction[n].propre++;
				if (vus.insert(n).second) par_fonction[n].inclusif++;
			}
			if (pile.size() > 1) {
				appelants[Nom(pile[1] - 1) + "  <-  " + Nom(pile[0])]++;
			}
			// Pile de 10 niveaux (feuille d'abord), pour les attentes et les points chauds.
			// 13/11 : nom du fil en tête de pile (chargement : savoir quel fil attend quoi).
			std::string cle = "[";
			for (const wchar_t ch: c.nom) cle += ch < 128 ? static_cast<char>(ch) : '?';
			cle += "] ";
			for (size_t i = 0; i < pile.size() && i < 14; i++) {
				cle += (i ? "\n         < " : "") + Nom(i == 0 ? pile[i] : pile[i] - 1);
			}
			piles[cle]++;
		}
		Sleep(static_cast<DWORD>(pas_ms));
	}
	timeEndPeriod(1);

	std::fwprintf(out, L"Échantillons : %llu (échecs de pile %llu) sur %zu fil(s) :", echantillons, echecs,
	              cibles.size());
	for (const auto& c: cibles) std::fwprintf(out, L" [%lu %ls]", c.tid, c.nom.c_str());
	std::fwprintf(out, L"\n");
	std::vector<std::pair<std::string, Compte>> v(par_fonction.begin(), par_fonction.end());
	const double                                total = static_cast<double>(std::max<uint64_t>(1, echantillons));
	auto                                        Liste = [&](bool propre, size_t n) {
		std::sort(v.begin(), v.end(), [&](const auto& a, const auto& b) {
			return propre ? a.second.propre > b.second.propre : a.second.inclusif > b.second.inclusif;
		});
		std::fwprintf(out, propre ? L"\n== Temps propre (%% des échantillons) ==\n" : L"\n== Temps inclusif ==\n");
		for (size_t i = 0; i < v.size() && i < n; i++) {
			std::fwprintf(out, L"%6.2f %6.2f  %hs\n", 100.0 * v[i].second.propre / total,
			              100.0 * v[i].second.inclusif / total, v[i].first.c_str());
		}
	};
	Liste(true, 80);
	Liste(false, 120);
	std::vector<std::pair<std::string, uint64_t>> a(appelants.begin(), appelants.end());
	std::sort(a.begin(), a.end(), [](const auto& x, const auto& y) { return x.second > y.second; });
	std::fwprintf(out, L"\n== Feuilles par appelant ==\n");
	for (size_t i = 0; i < a.size() && i < 60; i++) {
		std::fwprintf(out, L"%6.2f  %hs\n", 100.0 * a[i].second / total, a[i].first.c_str());
	}
	// Lignes de source les plus chaudes (temps propre), si le PDB a les numéros de ligne (/Z7).
	std::unordered_map<std::string, uint64_t> par_ligne;
	for (const auto& [adresse, n]: lignes_feuille) {
		IMAGEHLP_LINE64 li {sizeof(li)};
		DWORD           dep = 0;
		char            t[64];
		std::string     cle;
		if (SymGetLineFromAddr64(proc, adresse, &dep, &li)) {
			std::string f = li.FileName;
			const auto  s = f.find("src\\");
			std::snprintf(t, sizeof(t), ":%lu", li.LineNumber);
			cle = (s == std::string::npos ? f : f.substr(s + 4)) + t + "  " + Nom(adresse);
		} else {
			cle = "?  " + Nom(adresse);
		}
		par_ligne[cle] += n;
	}
	std::vector<std::pair<std::string, uint64_t>> pl(par_ligne.begin(), par_ligne.end());
	std::sort(pl.begin(), pl.end(), [](const auto& x, const auto& y) { return x.second > y.second; });
	std::fwprintf(out, L"\n== Lignes les plus chaudes (temps propre) ==\n");
	for (size_t i = 0; i < pl.size() && i < 80; i++) {
		std::fwprintf(out, L"%6.2f  %hs\n", 100.0 * pl[i].second / total, pl[i].first.c_str());
	}
	std::vector<std::pair<std::string, uint64_t>> pv(piles.begin(), piles.end());
	std::sort(pv.begin(), pv.end(), [](const auto& x, const auto& y) { return x.second > y.second; });
	std::fwprintf(out, L"\n== Piles les plus fréquentes (14 niveaux) ==\n");
	for (size_t i = 0; i < pv.size() && i < 400; i++) { // 13/11 : toutes les piles distinctes (fils figés)
		std::fwprintf(out, L"%6.2f  %hs\n", 100.0 * pv[i].second / total, pv[i].first.c_str());
	}
	if (out != stdout) fclose(out);
	SymCleanup(proc);
	return 0;
}
