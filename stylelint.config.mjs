export default {
  extends: ['stylelint-config-standard-scss'],
  ignoreFiles: ['build/**/*', 'node_modules/**/*'],
  overrides: [{ files: ['**/*.vue'], customSyntax: 'postcss-html' }],
  rules: {
    'scss/at-rule-no-unknown': [true, { ignoreAtRules: ['reference'] }],
  },
}
