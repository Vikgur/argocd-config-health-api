# Оглавление

- [О проекте](#о-проекте)  
- [Архитектура и настройки](#архитектура-и-настройки)  
- [Как применять и управлять](#как-применять-и-управлять)  
- [Внедренные DevSecOps практики](#внедренные-devsecops-практики)  
  - [AppProjects: изоляция окружений и контроль доступа](#appprojects-изоляция-окружений-и-контроль-доступа)  
  - [SSO: Назначение, подготовка, реализация](#sso-назначение-подготовка-реализация)  
    - [Назначение](#назначение)  
    - [Шаги настройки (GitHub)](#шаги-настройки-github)  
    - [Поддержка двух способов авторизации](#поддержка-двух-способов-авторизации)  
  - [RBAC: разграничение доступа](#rbac-разграничение-доступа)  
    - [Важное условие](#важное-условие)  
- [Linting и валидация](#linting-и-валидация)

---

# О проекте

Данный репозиторий представляет собой ядро GitOps-конфигурации для Argo CD веб-приложения [`health-api`](https://github.com/vikgur/health-api-for-microservice-stack): он определяет все критически важные элементы управления — **AppProjects**,**Авторизацию (SSO или по обычному логину)**, **RBAC-политику**,  подключение **Git-репозиториев**, а также параметры контроллера и кастомные health checks.

Сам Argo CD не управляет этим репозиторием — напротив, **этот репозиторий управляет Argo CD**.  

Конфигурация применяется декларативно через `kustomize build` и `kubectl apply`, в рамках инфраструктурного пайплайна на базе Ansible.

Применение и автоматизация настроены через Ansible-проект:  
[`ansible-gitops-bootstrap-health-api`](https://github.com/vikgur/ansible-gitops-bootstrap-health-api)

---

# Архитектура и настройки

* **AppProjects** (`argocd/projects/`)

  * `project-stage.yaml` — окружение `stage`, namespace `health-api-stage`, доступ только к разрешённым Git-репозиториям.
  * `project-prod.yaml` — окружение `prod`, namespace `health-api`, с включённым sync-окном (доступен деплой только в рабочее время).

* **Git-репозитории** (`argocd/repos/`)

  * `repo-gitops-apps.yaml` — доступ к репозиторию `gitops-apps-health-api`, где описаны Argo CD Applications.
  * `repo-helm-charts.yaml` — доступ к репозиторию `helm-blue-green-canary-gitops-health-api`, где хранятся Helm-чарты сервисов.

* **Конфигурация контроллера Argo CD** (`argocd/cm/argocd-cm.yaml`)

  * Установка ключа `application.instanceLabelKey` для корректного связывания ресурсов.
  * Кастомные health checks для CRD ресурсов (например, Rollout).
  * Настройка таймаутов reconciliation.

* **RBAC-настройки** (`argocd/cm/argocd-rbac-cm.yaml`)

  * Определены роли: `admin` и `stage-admin`.
  * Прописаны политики доступа для групп (`g:devops`, `g:qa`).

* **Файл argocd/kustomization.yaml**

  * Централизованная точка входа для применения всей конфигурации через команду `kustomize build . | kubectl apply -f -`.

---

# Как применять и управлять

```bash
# Установить kustomize, если не установлен
sudo snap install kustomize

# Применить всю конфигурацию Argo CD из этого репозитория
kustomize build . | kubectl apply -f -
```

---

# Внедренные DevSecOps практики

Репозиторий реализует безопасную декларативную конфигурацию доступа в Argo CD:

## AppProjects: изоляция окружений и контроль доступа

Ограничения описаны в файлах `argocd/projects/`:

- жёсткая привязка к namespace и Git-репозиториям для каждого окружения (`stage`, `prod`)
- включены предупреждения об осиротевших ресурсах (`orphanedResources.warn`)
- для окружения `prod` задано sync-окно — деплой возможен только в рабочее время

## SSO: Назначение, подготовка, реализация

### Назначение

**Цель:** безопасный централизованный вход в Argo CD через GitHub, без ручных логинов.

- Пользователь входит через GitHub OAuth  
- Argo CD получает `email`, `username`, `groups`  
- Группы (`g:devops`, `g:qa`) управляют доступом через `argocd-rbac-cm.yaml`

### Шаги настройки (GitHub)**

1. **Зарегистрировать OAuth App в GitHub:**

   - Перейди: `GitHub → Settings → Developer settings → OAuth Apps`
   - Нажми **New OAuth App**:
     - Application Name: `Argo CD SSO`
     - Homepage URL: `https://argocd.health.gurko.ru`
     - Authorization callback URL для OIDC:  
       `https://argocd.health.gurko.ru/auth/callback`
     - Authorization callback URL для DEX:  
       `https://argocd.health.gurko.ru/api/dex/callback`

2. **Скопировать:**
   - `Client ID`
   - `Client Secret`

3. **Вставить в [ansible-gitops-bootstrap-health-api](https://github.com/Vikgur/ansible-gitops-bootstrap-health-api/) в [ansible/group_vars/master.yaml](https://github.com/Vikgur/ansible-gitops-bootstrap-health-api/-/blob/main/ansible/group_vars/master.yaml):**

   ```yaml
   github_oauth_client_id: YOUR_CLIENT_ID
   github_oauth_client_secret: YOUR_CLIENT_SECRET
   argocd_sso_mode: oidc # или dex
   ```

### Поддержка двух способов авторизации

Репозиторий содержит два независимых подхода авторизации в Argo CD:

- **OIDC напрямую через GitHub (выбран как основной)** — используется в продакшене, настраивается в `argocd-cm.yaml`, без дополнительных компонентов. В связанном репозитории [ansible-gitops-bootstrap-health-api](https://github.com/Vikgur/ansible-gitops-bootstrap-health-api/) в [ansible/group_vars/master.yaml](https://github.com/Vikgur/ansible-gitops-bootstrap-health-api/-/blob/main/ansible/group_vars/master.yaml) выбран `argocd_namespace: argocd`.
- **Dex + GitHub OAuth** — дополнительный демонстрационный вариант для целей портфолио, расположен в `argocd-cm-dex.yaml`.

Оба файла можно применить вручную через `kubectl apply`, в зависимости от требуемой конфигурации.

Активный вариант указывается через файл `argocd/cm/argocd-cm-*.yaml`, остальные закомментированы в `kustomization.yaml`

#### Почему выбран OIDC:

- Упрощает архитектуру: меньше компонентов = меньше точек отказа.
- Настраивается напрямую в `argocd-cm.yaml` через `oidc.config`.
- Лучше подходит для облачных CI/CD систем (GitHub, github, Okta).
- Используется в production-кластерах крупных компаний.

Dex — более «архитектурный» способ, используется, если у компании несколько провайдеров (GitHub, github, LDAP и т.д.). Dex оставлен в проекте **для демонстрации альтернативного варианта**.

## RBAC: разграничение доступа

Конфигурация `argocd/cm/argocd-rbac-cm.yaml` задаёт роли и права доступа в Argo CD:

- **Роль `admin`** — полный доступ ко всем приложениям и проектам (`stage` и `prod`)
- **Роль `stage-admin`** — доступ только к окружению `stage`, без прав на `prod`

Роли назначаются группам:

- `g:devops` → получает роль `admin`
- `g:qa` → получает роль `stage-admin`

Это разграничение позволяет ограничить доступ к `prod`, оставить `stage` для QA, и исключить случайные действия вне зоны ответственности. Все права описаны декларативно и управляются через GitOps.

### Важное условие

g:devops, g:qa должны быть GitHub Teams при использовании orgs.
Если вход по обычным пользователям — можно использовать login:<user> вместо g:…

## Linting и валидация

В рамках GitOps-подхода конфигурация Argo CD оформлена как декларативный код.  
Чтобы обеспечить структурную целостность, читаемость и соответствие Kubernetes-спецификациям, в проект внедрены базовые линтеры.  
Проверки минимальны, но обязательны — они позволяют гарантировать, что любые изменения в конфигурации Argo CD проходят автоматическую валидацию перед применением.

Для обеспечения корректности YAML-конфигураций и ресурсов Kubernetes в репозитории подключены pre-commit хуки:

- **yamllint** — проверка структуры и синтаксиса YAML
- **ct lint** — валидация Kubernetes-манифестов (проверка схем, корректности ключей и т.д.)

Конфигурация хуков описана в [.pre-commit-config.yaml](./.pre-commit-config.yaml) и запускается автоматически при каждом коммите.

Запуск вручную:

```bash
pre-commit run --all-files
```