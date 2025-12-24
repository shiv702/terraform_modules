variable "name_prefix" { type = string }
variable "vpc_cidr" { type = string }

variable "subnets" {
  type = map(object({
    cidr = string
    az   = string
    type = string
    tags = optional(map(string), {})
  }))
}

variable "nat_gateway_strategy" {
  type    = string
  default = "single"
}

variable "tags" {
  type    = map(string)
  default = {}
}
