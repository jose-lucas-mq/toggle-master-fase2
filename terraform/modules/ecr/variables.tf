variable "name_prefix" { type = string }
variable "tags" { type = map(string) }
variable "repos" {
  description = "Lista de { name, (optional) scan_on_push, (optional) immutability, (optional) keep_last_n_images }"
  type = list(object({
    name                 = string
    scan_on_push         = optional(bool, true)
    image_tag_mutability = optional(string, "MUTABLE")
    keep_last_n_images   = optional(number, 10)
  }))
}
