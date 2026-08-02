# Contributing

## Requirements

- Node.js 22.12 or newer
- Bun 1.3.14

Install dependencies:

```bash
bun install --frozen-lockfile
```

## Component structure

Each public component lives in its own directory:

```text
src/components/<component>/
├── <Component>.vue
├── <Component>.module.scss
├── <Component>.stories.ts
├── <Component>.test.ts
├── <component>.types.ts
└── index.ts
```

Wrappers must use the corresponding Nuxt UI component. Do not recreate behavior that Nuxt UI already provides.

Public root customization remains supported:

```vue
<Button class="button card_button" data-test="submit" />
```

The wrapper must forward `class`, `style`, listeners, ARIA attributes and all `data-*` attributes. Do not expose Nuxt UI's `ui` prop from wrapper types because it allows consumers to override internal slot classes.

Additional component styles belong in SCSS Modules. Global Tailwind and Nuxt UI imports belong only in `src/styles/main.css`.

## Required checks

```bash
bun run format:check
bun run lint
bun run stylelint
bun run typecheck
bun run test
bun run test:coverage
bun run build
bun run build:storybook
bun run pack
```

All generated files must remain inside `build/`.
