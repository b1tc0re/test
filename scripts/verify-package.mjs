import { access, readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const rootDir = resolve(import.meta.dirname, '..')
const packageJson = JSON.parse(await readFile(resolve(rootDir, 'package.json'), 'utf8'))
const buttonExport = packageJson.exports['./button']

if (!buttonExport?.types || !buttonExport?.import) {
  throw new Error('package.json must expose both types and import for ./button')
}

for (const target of [buttonExport.types, buttonExport.import]) {
  await access(resolve(rootDir, target))
}

const buttonEntry = await readFile(resolve(rootDir, buttonExport.import), 'utf8')

if (!buttonEntry.includes("import '../../assets/ui.css'")) {
  throw new Error('The button entry does not import its generated CSS')
}

await access(resolve(rootDir, 'build/dist/assets/ui.css'))
console.log('Package exports and component CSS import are valid.')
