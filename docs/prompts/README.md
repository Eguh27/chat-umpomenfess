# Prompt agent

Cara pakai (opencode): buka project, pilih mode & model sesuai file prompt, tempel isi file prompt sebagai pesan pertama.
Jalankan **satu agent per peran**, urut per Wave di `TODO.md`. Agent yang sama boleh dipakai ulang untuk wave berikutnya.

| Urutan | File | Peran | Mode | Model |
|---|---|---|---|---|
| Wave 0 | `agent-L.md` | Lead/ops | Build | ringan-menengah |
| Wave 1 | `agent-D.md` | Database | Build | terkuat |
| Wave 1 | `agent-F.md` | Frontend | Build | ringan |
| Wave 2 | `agent-B.md` | Backend/API | Build | menengah-kuat |
| Wave 2 | `agent-R.md` | Realtime client | Build | menengah-kuat |
| Wave 3 | `agent-F.md` | Frontend (lanjut) | Build | ringan |
| Wave 4 | `agent-S.md` | Security/QA | Plan lalu Build | terkuat |
| Wave 5 | `agent-L.md` | Lead/ops | Build | ringan-menengah |

Aturan umum untuk SEMUA prompt: baca `AGENTS.md` dahulu. Jika spesifikasi bertentangan atau kurang, tulis `REQUEST` di `docs/progress.md` lalu berhenti pada bagian itu. Jangan menebak kontrak.
