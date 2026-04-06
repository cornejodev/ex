# 🗃 CIS Core Automations

> Unified codebase for automating key workflows and data operations for CIS.

<a name="readme-top"></a>

## Table of Contents:

- [🚨 Prerequisites](#-prerequisites)
- [🏛️ Project Structure](#️-project-structure)
  - [Files and Folders Naming Conventions](#files-and-folders-naming-conventions)
  - [File Naming Convention](#file-naming-convention)
- [🏇 Automation Execution and Test Report Generation](#-automation-execution-and-test-report-generation)
  - [Poetry commands](#poetry-commands)
  - [Executing Automations](#executing-automations)
    - [Local (for development)](#local-for-development)
    - [Docker Container (for development)](#docker-container-for-development)
    - [GitHub Actions (Production)](#github-actions-production)
  - [Automation Results](#automation-results)
- [🤿 VPN](#-vpn)

## 🚨 Prerequisites

- Must have the following tools for local development and execution:
  - [Python 3.12 or higher](https://www.python.org/)
  - [Poetry 2.1.3 or higher](https://python-poetry.org/)
  - [Docker](https://www.docker.com/get-started/)

## 🏛️ Project structure

### Files and Folders Naming Conventions

- This project adheres to the
  [JHIT Development Guidelines](https://github.com/corp-interuniversitaria-de-servicios/jhit-development-guidelines),
  along with the additional project-specific standards outlined below.

- `snake_case` - **Only** snake case is used when naming folders and when naming
  files regardless of their extension (`*.js`, `*.go`, etc...).
  - **Exceptions:** files with an already **predefined universally accepted
    naming convention** such as `Dockerfile` and `README.md`

```
├── auto      <-- Executable automations live here
├── bin       <-- Executables needed for running the project
├── utils     <-- Helper functions
├── cli       <-- Command line handler logic lives here
|
├── artifacts      <-- Directory created at runtime. Contains input and output data
├── tmp            <-- Directory created at runtime. Used as a temporary directory for storing non persistent data
├── logs           <-- Directory created at runtime. Used for storing logs
|
├── main.py        <--  Entry point of the application; coordinates CLI parsing and automation dispatch
|
├── .github
│   └── workflows         
│        └── prod.yml    <-- Github Actions config file
|
├── .dockerignore
├── .gitignore
├── pyproject.toml
├── poetry.lock
├── Dockerfile
├── pytest.ini          <-- Pytest behavior config file
└── README.md
```

### File Naming Convention

To maintain clarity and avoid overly verbose filenames, this project adopts a
`<domain>_XX_<responsibility>.py` naming convention for automation scripts.

#### Prefixes per Domain

| Domain       | Prefix | Example Filename |
| ------------ | ------ | ---------------- |
| SECOP        | scp    | scp_01.py        |
| DIAN         | dian   | dian_01.py       |
| SURA EPS     | sura   | sura_01.py       |
| Colmena      | colm   | colm_01.py       |
| Antecedentes | ant    | ante_01.py       |
| Comfama      | cfma   | cfma_01.py       |

Each `*_exec` module is considered the **main entrypoint** for an automation
from a particular domain and **must** include a documentation block using the
following format. This ensures every automation has clear, standardized metadata
for easier understanding and maintenance:

```python
# dian_01_exec.py
"""
===============================================================================
                          Module: auto.dian.dian_01
===============================================================================
Business Domain ID: 109
------------

Business Domain Name: Consulta DIAN
------------

Module Type: Webpage Automation (Chrome)
------------

Description:
------------
This module does the following:

1. Downloads a spreadsheet from a Microsoft Sharepoint Drive
2. Consumes a spreasheet that maps to CUFERecord schema
3. Navigates to DIAN webpage
4. For each entry in the Spreadsheet checks events related to said entry (aceptacion, acuse, sin evento)
via webpage UI
5. Downloads a PDF certificate for an entry ONLY if said entry has an event status of aceptacion or acuse, otherwise
doesn't download anything
6. Generates an spreadsheet that contains the following columns:

    1. cliente
    2. cufe
    3. evento

7. Uploads a zipfile to the same Microsoft Sharepoint Drive from step 1 containing the following:

    1. Original spreadsheet used as input data in step 1
    2. Generated spreasheet from step 6
    3. Downloaded PDFs from step 5


Additional Notes:
---------------
1. IMPORTANT: The spreadsheet data consumed in step 1 is post-processed output payload from cis-micro-kerberos microservice

2. This module has a built-in retry automation execution functions that are triggered when there is a failure in solving the CAPTCHA
when executing the automation steps in the webpage UI. Said functions are:

    1. dian_invoices_first_execution_round
    2. dian_invoices_second_execution_round


Version:       1.0
Created:  21-05-2025

===============================================================================
"""
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## 🏇 Automation Execution and Test Report Generation

### Poetry commands

- 🚨 **Important:** Configure virtual environment creation to always be in the
  **root of a project**

```
poetry config virtualenvs.in-project true
```

#### MacOS

Create virtual envirnoment:

##### Step 1.

```
poetry env use python3
```

##### Step 2.

```
eval $(poetry env activate)
```

### Executing automations

#### Local **(for development)**

- **Note:** runs in headed by default
  - With arguments:
  ```bash
  ./bin/run_local.sh --dp <department_name> --auto <automation_id>
  ```

Example:

```bash
./bin/run_local.sh --dp pruebas --auto demo-00
```

#### Docker Container **(for development)**

- **Note:** runs in headless by default and must be ran as a smoke test before
  pushing remotely
  - With arguments:
    ```bash
    ./bin/run_docker.sh --dp <department_name> --auto <automation_id>
    ```

#### Github Actions **(Production)**

- Workflow dispatch is enabled, therefore user can **execute pipelines
  manually** via **Gtihub Actions UI**.
- Addiitonally arguments can be provided to specify which automations under
  `auto/` to execute.

- `prod.yml` file excerpt with `workflow_dispatch` configuration enabled:

```yaml
name: CIS Automations (PROD)

on:
    workflow_dispatch:
        inputs:
            automation_args:
                description: "CLI arguments to pass to main.py (e.g. --dp pruebas --auto ante-01)"
                required: false

concurrency:
    group: "cis-${{ inputs.automation_args }}"
    cancel-in-progress: false

run-name: "CIS -> ${{ inputs.automation_args || 'NO_ARGS' }}"
```

### Automation results

- Each automation will create a list of artifacts in the `/artifacts` directory
  which contains metadata and data files which will then be sent back to the
  user after automation execution..

## 🤿 VPN

- Some automations need a VPN connection. The file that handles this is the
  `vpn_setup.sh` bash script. Which sets up a wireguard VPN connection and has a
  hardcoded list of automation IDs that requiere a VPN for successful execution.
  This bash script is ran automatically by the `prod.yml` file in production
  workflow executions.

```bash
#!/usr/bin/env bash

set -euo pipefail

# Example usage: ./setup_vpn.sh --auto se-02
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --auto)
      AUTO_VALUE="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# List of automations that require VPN
VPN_REQUIRED_AUTOMATIONS=("se-02" "demo-00")


for item in "${VPN_REQUIRED_AUTOMATIONS[@]}"; do
  if [[ "$AUTO_VALUE" == "$item" ]]; then
    exit 0  # VPN needed
  fi
done

exit 1  # VPN not needed
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>
