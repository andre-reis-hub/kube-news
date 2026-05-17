# Módulos

Coloque módulos Terraform reutilizáveis aqui, cada um em seu próprio subdiretório:

```
modules/
└── <nome-modulo>/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── README.md
```

Para referenciar um módulo a partir de um ambiente:

```hcl
module "<nome>" {
  source = "../../modules/<nome-modulo>"

  # passe as variáveis necessárias
}
```
