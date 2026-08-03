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

const componentEntries = readdirSync(componentsDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => resolve(componentsDir, entry.name, 'index.js'))
  .filter(existsSync)

assert(componentEntries.length > 0, 'No component entry files were generated.')

const importedCssFiles = new Set()
const emittedFiles = filesRecursively(distDir)
let buttonCss = ''

assert(
  emittedFiles.every((file) => !file.replaceAll('\\', '/').includes('/src/components/')),
  'Declarations must not contain a nested src/components directory.',
)

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

    if (componentName === 'button') {
      buttonCss += readFileSync(cssFile, 'utf8')
    }
  }
}

assert(
  emittedFiles.every((file) => basename(file) !== 'ui.css'),
  'A shared ui.css was emitted; component CSS must stay split.',
)

console.log('Button CSS output:')
console.log(buttonCss)

assert(buttonCss, 'Button entry does not import CSS.')
assert(/display:\s*inline-flex/.test(buttonCss), 'Tailwind @apply did not emit display:inline-flex.')
assert(/align-items:\s*center/.test(buttonCss), 'Tailwind @apply did not emit align-items:center.')
assert(/justify-content:\s*center/.test(buttonCss), 'Tailwind @apply did not emit justify-content:center.')

console.log(`Verified ${componentEntries.length} component entry and ${importedCssFiles.size} imported CSS file(s).`)
