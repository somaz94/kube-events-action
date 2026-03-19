# kube-events-action

[![CI](https://github.com/somaz94/kube-events-action/actions/workflows/ci.yml/badge.svg)](https://github.com/somaz94/kube-events-action/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Latest Tag](https://img.shields.io/github/v/tag/somaz94/kube-events-action)](https://github.com/somaz94/kube-events-action/tags)
[![Top Language](https://img.shields.io/github/languages/top/somaz94/kube-events-action)](https://github.com/somaz94/kube-events-action)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Kube%20Events%20Action-blue?logo=github)](https://github.com/marketplace/actions/kube-events-action)

A GitHub Action that checks Kubernetes cluster events using [kube-events](https://github.com/somaz94/kube-events), and optionally posts the report as a PR comment.

<br/>

## Features

- Check cluster events after deployment with **warning threshold**
- Auto-post event reports as **PR comments** (updates existing comment on re-run)
- Multiple output formats: `color`, `plain`, `json`, `markdown`, `table`
- Group events by **resource**, **namespace**, **kind**, or **reason**
- Filter by **namespace**, **kind**, **name**, **type**, and **reason**
- Configurable time window with `since`
- Fail CI when warning count exceeds threshold

<br/>

## Quick Start

```yaml
- name: Check cluster events
  uses: somaz94/kube-events-action@v1
  with:
    namespace: production
    type: Warning
    since: 10m
```

<br/>

## Usage

### Post-deploy warning check

```yaml
name: Post-deploy Check
on:
  workflow_run:
    workflows: ["Deploy"]
    types: [completed]

jobs:
  event-check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - name: Setup kubeconfig
        run: echo "${{ secrets.KUBECONFIG }}" > /tmp/kubeconfig

      - name: Check events
        id: events
        uses: somaz94/kube-events-action@v1
        with:
          namespace: production
          type: Warning
          since: 10m
          threshold: '5'
          comment: 'true'
        env:
          KUBECONFIG: /tmp/kubeconfig

      - name: Fail if too many warnings
        if: steps.events.outputs.has-warnings == 'true'
        run: |
          echo "Warning count: ${{ steps.events.outputs.warning-count }}"
          exit 1
```

### Filter by kind and reason

```yaml
- uses: somaz94/kube-events-action@v1
  with:
    namespace: production
    kind: Pod
    reason: BackOff,Unhealthy,Failed
    since: 5m
    output: table
    comment: 'false'
```

### All namespaces summary

```yaml
- uses: somaz94/kube-events-action@v1
  with:
    all-namespaces: 'true'
    type: Warning
    since: 1h
    summary-only: 'true'
```

### Group events by namespace

```yaml
- uses: somaz94/kube-events-action@v1
  with:
    all-namespaces: 'true'
    group-by: namespace
    type: Warning
    since: 10m
```

### Group events by reason

```yaml
- uses: somaz94/kube-events-action@v1
  with:
    namespace: production
    group-by: reason
    since: 10m
    output: table
    comment: 'false'
```

### JSON output for downstream processing

```yaml
- name: Get event report
  id: events
  uses: somaz94/kube-events-action@v1
  with:
    namespace: production
    output: json
    comment: 'false'

- name: Process result
  run: echo '${{ steps.events.outputs.result }}' | jq '.summary.warningCount'
```

### Scheduled cluster health audit

```yaml
name: Cluster Health Audit
on:
  schedule:
    - cron: '0 8 * * *'

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - name: Check warnings
        id: events
        uses: somaz94/kube-events-action@v1
        with:
          all-namespaces: 'true'
          type: Warning
          since: 24h
          output: json
          comment: 'false'

      - name: Notify Slack
        if: steps.events.outputs.has-warnings == 'true'
        run: |
          curl -X POST "${{ secrets.SLACK_WEBHOOK }}" \
            -d "{\"text\": \"Cluster warnings: ${{ steps.events.outputs.warning-count }} in last 24h\"}"
```

<br/>

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `namespace` | Filter by namespace (comma-separated) | No | all |
| `kind` | Filter by involved object kind (comma-separated) | No | all |
| `name` | Filter by involved object name (comma-separated) | No | all |
| `type` | Filter by event type: `Normal`, `Warning` | No | all |
| `reason` | Filter by event reason (comma-separated) | No | all |
| `since` | Show events newer than duration (e.g., `5m`, `1h`) | No | `10m` |
| `group-by` | Group events by: `resource`, `namespace`, `kind`, `reason` | No | `resource` |
| `output` | Output format: `color`, `plain`, `json`, `markdown`, `table` | No | `markdown` |
| `summary-only` | Show summary statistics only | No | `false` |
| `all-namespaces` | Show events from all namespaces | No | `false` |
| `threshold` | Fail if warning count exceeds this value (0 = do not fail) | No | `0` |
| `comment` | Post result as PR comment | No | `true` |
| `version` | kube-events version to install | No | `latest` |
| `token` | GitHub token for PR comments | No | `${{ github.token }}` |

<br/>

## Outputs

| Output | Description |
|--------|-------------|
| `result` | Full event report output text |
| `warning-count` | Number of warning events detected |
| `has-warnings` | `true` if warnings were detected, `false` otherwise |

<br/>

## Threshold Behavior

The action **does not fail** by default when warnings are detected. Set `threshold` to control failure behavior:

```yaml
# Fail if more than 5 warnings
- uses: somaz94/kube-events-action@v1
  with:
    threshold: '5'

# Never fail (default)
- uses: somaz94/kube-events-action@v1
  with:
    threshold: '0'
```

Or use `has-warnings` output to control your workflow:

```yaml
- name: Fail on any warning
  if: steps.events.outputs.has-warnings == 'true'
  run: exit 1
```

<br/>

## Combined Usage with kube-diff-action

Use [kube-diff-action](https://github.com/somaz94/kube-diff-action) to detect manifest drift and `kube-events-action` to check cluster warnings — all in one workflow.

### Post-deploy validation

```yaml
name: Deploy & Validate
on:
  push:
    branches: [main]

jobs:
  deploy-and-validate:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - name: Check drift before deploy
        id: diff
        uses: somaz94/kube-diff-action@v1
        with:
          source: file
          path: ./manifests/
          namespace: production
          output: markdown
          comment: 'false'

      - name: Deploy manifests
        if: steps.diff.outputs.has-changes == 'true'
        run: kubectl apply -f ./manifests/

      - name: Check cluster events after deploy
        id: events
        uses: somaz94/kube-events-action@v1
        with:
          namespace: production
          type: Warning
          since: 5m
          threshold: '3'
          comment: 'true'

      - name: Summary
        run: |
          echo "Drift detected: ${{ steps.diff.outputs.has-changes }}"
          echo "Warnings after deploy: ${{ steps.events.outputs.warning-count }}"
```

### Scheduled cluster health check

```yaml
name: Cluster Health Check
on:
  schedule:
    - cron: '0 */6 * * *'

jobs:
  health-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check manifest drift
        id: diff
        uses: somaz94/kube-diff-action@v1
        with:
          source: kustomize
          path: ./overlays/production/
          output: json
          comment: 'false'

      - name: Check cluster warnings
        id: events
        uses: somaz94/kube-events-action@v1
        with:
          all-namespaces: 'true'
          type: Warning
          since: 6h
          output: json
          comment: 'false'

      - name: Notify on issues
        if: steps.diff.outputs.has-changes == 'true' || steps.events.outputs.has-warnings == 'true'
        run: |
          curl -X POST "${{ secrets.SLACK_WEBHOOK }}" \
            -d "{\"text\": \"🔍 Cluster issues detected\nDrift: ${{ steps.diff.outputs.has-changes }}\nWarnings: ${{ steps.events.outputs.warning-count }}\"}"
```

<br/>

## License

This project is licensed under the Apache License 2.0 — see the [LICENSE](LICENSE) file for details.
