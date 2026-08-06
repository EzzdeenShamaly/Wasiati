// @ts-check
import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';

// Flat config (ESLint 9). This is the repo's FIRST lint setup: CI has been calling
// `pnpm lint` against an eslint that was never installed or configured, so the job
// died here and tsc/test/build never ran. The ruleset is deliberately close to Nest's
// own scaffolding — recommended + the relaxations Nest ships — so it gates real
// defects on an already-written codebase instead of demanding a mass restyle.
export default tseslint.config(
  {
    // Build output and generated Prisma client are not ours to lint.
    ignores: ['dist/**', 'node_modules/**', 'coverage/**', '.ts-node/**'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      // TypeScript resolves identifiers itself and CI runs `tsc --noEmit`; core no-undef
      // duplicates that badly on TS (it flags node/DOM globals the compiler knows about).
      'no-undef': 'off',

      // Nest's own scaffolding turns these off. `any` appears in this codebase at the
      // Prisma/Express boundaries where it is load-bearing, and requiring explicit return
      // types on every provider method would be a repo-wide rewrite, not a defect gate.
      '@typescript-eslint/no-explicit-any': 'off',

      // `import * as express from 'express'` / `import * as cookieParser from ...` is the
      // CommonJS-interop form Nest documents and this codebase uses throughout.
      '@typescript-eslint/no-namespace': 'off',

      // `import Stripe = require('stripe')` is REQUIRED, not sloppiness: stripe's CJS build
      // uses `export =` and this tsconfig has no esModuleInterop, so a default import is
      // undefined at runtime (allowSyntheticDefaultImports only silences the type error).
      // allowAsImport keeps the rule's real value — bare require() calls still error.
      '@typescript-eslint/no-require-imports': ['error', { allowAsImport: true }],

      // Unused ARGS are common and harmless in Nest signatures (guards/filters/interceptors
      // receive positional params they may ignore); unused LOCALS are still a real smell,
      // so only silence the leading-underscore opt-out. ignoreRestSiblings covers the
      // `const { passwordHash, ...safe } = user` idiom used to STRIP secrets before
      // returning a row — that omission is the point, and must not be linted away.
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
          ignoreRestSiblings: true,
        },
      ],
    },
  },
);
