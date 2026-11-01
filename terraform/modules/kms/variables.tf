variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "seguros-horizonte"
}

variable "deletion_window_in_days" {
  description = "Dias de espera antes de apagar uma chave (7 a 30)"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days deve ficar entre 7 e 30 (limite da AWS)."
  }
}
