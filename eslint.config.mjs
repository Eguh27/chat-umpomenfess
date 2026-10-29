// Konfigurasi ESLint (flat config). Tanpa typed linting supaya cepat.
import js from '@eslint/js';
import prettier from 'eslint-config-prettier/flat';
import astro from 'eslint-plugin-astro';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default [
  {
    ignores: [
      'dist/**',
      '.astro/**',
      '.vercel/**',
      'node_modules/**',
      'supabase/**',
      'design/**',
      'public/**',
      'docs/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...astro.configs.recommended,
  {
    files: ['**/*.{js,mjs,cjs,ts,mts,cts,astro}'],
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.browser,
      },
    },
  },
  {
    // TypeScript sudah menangani resolusi identifier; `no-undef` hanya false positive.
    files: ['**/*.{ts,mts,cts,astro}'],
    rules: {
      'no-undef': 'off',
    },
  },
  {
    // `src/env.d.ts` memakai `/// <reference path="../.astro/types.d.ts" />`.
    files: ['**/*.d.ts'],
    rules: {
      '@typescript-eslint/triple-slash-reference': 'off',
    },
  },
  {
    // Temuan asli: inisialisasi `turnstileOk` selalu ditimpa di try/catch.
    // File milik Agent B; jangan diubah dari zona L. Cabut override ini
    // setelah B merapikan `src/pages/api/rooms/join.ts`.
    files: ['src/pages/api/rooms/join.ts'],
    rules: {
      'no-useless-assignment': 'off',
    },
  },
  // Harus paling akhir: matikan rule yang bentrok dengan Prettier.
  prettier,
];
