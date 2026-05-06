---
title: Productive K3S
template: home.html
hide:
  - navigation
  - toc
eyebrow: Single-node Kubernetes, done right
eyebrow_es: Kubernetes de nodo único, bien hecho
hero_title: Productive K3S
hero_title_es: Productive K3S
lead: Productive K3S provides a simple way to run a production-like Kubernetes environment on a single virtual machine.
lead_es: Productive K3S ofrece una forma simple de ejecutar un entorno Kubernetes similar a producción sobre una única máquina virtual.
sublead: It is designed for teams that want to adopt Kubernetes practices without the operational overhead and cost of managing a full multi-node cluster.
sublead_es: Está pensado para equipos que quieren adoptar prácticas de Kubernetes sin la sobrecarga operativa ni el costo de administrar un clúster completo de varios nodos.
primary_label: View on GitHub
primary_label_es: Ver en GitHub
primary_url: https://github.com/jemacchi/productive-k3s
secondary_label: Open README
secondary_label_es: Abrir README
secondary_url: https://github.com/jemacchi/productive-k3s/blob/main/README.md
card_title: What it does
card_title_es: Qué hace
card_items:
  - Deploys a single-node k3s cluster on a supported VM or host
  - Provides a Kubernetes-compatible environment out of the box
  - Enables real workloads using manifests, Helm charts, and Kubernetes-native tooling
card_items_es:
  - Despliega un clúster k3s de nodo único sobre una VM o un host soportados
  - Proporciona un entorno compatible con Kubernetes desde el inicio
  - Permite ejecutar workloads reales usando manifests, charts de Helm y tooling nativo de Kubernetes
why_title: Why it exists
why_title_es: Por qué existe
why_options:
  - label: Option 1
    text: A single VM with Docker Compose is simple, but not Kubernetes.
  - label: Option 2
    text: A full Kubernetes cluster is powerful, but complex and costly.
why_options_es:
  - label: Opción 1
    text: Una única VM con Docker Compose es simple, pero no es Kubernetes.
  - label: Opción 2
    text: Un clúster Kubernetes completo es potente, pero complejo y costoso.
bridge_note: Productive K3S bridges that gap.
bridge_note_es: Productive K3S cubre ese espacio intermedio.
bridge_points:
  - Work with Kubernetes from day one
  - Keep infrastructure simple, just one VM
  - Avoid premature complexity
bridge_points_es:
  - Trabajá con Kubernetes desde el primer día
  - Mantené la infraestructura simple, con una sola VM
  - Evitá complejidad prematura
use_cases_title: Target use cases
use_cases_title_es: Casos de uso objetivo
use_cases:
  - Small teams and startups
  - Early-stage platforms
  - Cost-sensitive environments
  - Development and lightweight production workloads
use_cases_es:
  - Equipos pequeños y startups
  - Plataformas en etapa temprana
  - Entornos sensibles al costo
  - Desarrollo y workloads productivos livianos
principles_title: Design principles
principles_title_es: Principios de diseño
principles:
  - title: Keep it simple
    text: single host, minimal setup
  - title: Stay Kubernetes-native
    text: no abstractions over k8s
  - title: Be migration-ready
    text: workloads can move to a real cluster later
principles_es:
  - title: Mantenelo simple
    text: host único, setup mínimo
  - title: Mantenete nativo de Kubernetes
    text: sin abstracciones por encima de k8s
  - title: Preparado para migrar
    text: los workloads pueden moverse luego a un clúster real
environments_title: Supported environments
environments_title_es: Entornos soportados
environments:
  - Ubuntu LTS
  - Debian 12 and Debian 13
  - Linux hosts and virtual machines used in development, validation, and small production-style setups
  - Optimized for standard cloud virtual machines across providers like AWS, GCP, and DigitalOcean.
environments_es:
  - Ubuntu LTS
  - Debian 12 y Debian 13
  - Hosts Linux y máquinas virtuales usadas en desarrollo, validación y pequeños entornos estilo producción
  - Optimizado para máquinas virtuales cloud estándar en proveedores como AWS, GCP y DigitalOcean.
not_title: What it is not
not_title_es: Qué no es
not_items:
  - Not a replacement for managed Kubernetes services such as EKS, GKE, or AKS
  - Not a multi-tenant platform
  - Not an excuse to skip production operational discipline
not_items_es:
  - No reemplaza servicios Kubernetes administrados como EKS, GKE o AKS
  - No es una plataforma multi-tenant
  - No es una excusa para omitir disciplina operativa de producción
not_note: Instead, it is a pragmatic entry point into Kubernetes.
not_note_es: En cambio, es un punto de entrada pragmático a Kubernetes.
---
