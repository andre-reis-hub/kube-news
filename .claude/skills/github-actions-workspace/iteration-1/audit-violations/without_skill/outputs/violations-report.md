# Análise do workflow

O workflow tem alguns problemas:

- Usa `actions/checkout@main` — melhor usar `@v4`
- A tag `latest` na imagem Docker não é ideal
- Poderia usar `github.sha` para rastrear commits

## Sugestão

Trocar `@main` por `@v4` no checkout.
