import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { basename, dirname, resolve } from 'node:path'

const distDir = resolve('build/dist')
const componentsDir = resolve(distDir, 'components')

function assert(condition, message) {
  if (!condition) {
    throw new Error(message)
  }
}

function filesRecursively(directory) {
  if (!existsSync(directory)) {
    return []
  }

  return readdirSync(directory).flatMap((name) => {
    const path = resolve(directory, name)

    return statSync(path).isDirectory() ? filesRecursively(path) : [path]
  })
}

assert(existsSync(componentsDir), 'Missing build/dist/components directory.')
assert(!existsSync(resolve(componentsDir, 'src')), 'Declarations must not be emitted under build/dist/components/src.')

const componentEntries = readdirSync(componentsDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => resolve(componentsDir, entry.name, 'index.js'))
  .filter(existsSync)

assert(componentEntries.length > 0, 'No component entry files were generated.')

const importedCssFiles = new Set()

for (const entryFile of componentEntries) {
  const componentDir = dirname(entryFile)
  const componentName = basename(componentDir)
  const code = readFileSync(entryFile, 'utf8')
  const cssImports = [...code.matchAll(/import\s+["']([^"']+\.css)["'];?/g)].map((match) => match[1])

  assert(cssImports.length > 0, `${componentName} entry does not import its CSS.`)
  assert(existsSync(resolve(componentDir, 'index.d.ts')), `${componentName} declaration entry is missing.`)

  for (const cssImport of cssImports) {
    const cssFile = resolve(componentDir, cssImport)

    assert(existsSync(cssFile), `${componentName} imports missing CSS: ${cssImport}`)
    importedCssFiles.add(cssFile)
  }
}

const emittedFiles = filesRecursively(distDir)

assert(
  emittedFiles.every((file) => basename(file) !== 'ui.css'),
  'A shared ui.css was emitted; component CSS must stay split.',
)

const buttonCss = [...importedCssFiles]
  .map((file) => readFileSync(file, 'utf8'))
  .find((css) => css.includes('transition:transform 120ms ease'))

assert(buttonCss, 'Unable to identify the Button CSS output.')
assert(buttonCss.includes('display:inline-flex'), 'Tailwind @apply did not emit display:inline-flex.')
assert(buttonCss.includes('align-items:center'), 'Tailwind @apply did not emit align-items:center.')
assert(buttonCss.includes('justify-content:center'), 'Tailwind @apply did not emit justify-content:center.')

console.log(`Verified ${componentEntries.length} component entry and ${importedCssFiles.size} imported CSS file(s).`)
