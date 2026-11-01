# Configuração do tflint (linter do Terraform).
# Roda em cada pasta com --recursive, então cada módulo é checado sozinho.
config {
  call_module_type = "none"
}

# Regras da própria linguagem: variáveis sem tipo, versões faltando, código não usado
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Regras da AWS: tipos de instância inválidos, argumentos que a API rejeita etc.
plugin "aws" {
  enabled = true
  version = "0.36.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
