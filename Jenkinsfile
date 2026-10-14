pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    environment {
        DEPLOY_HOST = '192.168.1.32'
        DEPLOY_USER = 'deploy'
        APP_DIR = '/opt/flask-app'

        DOCKERHUB_REPO = 'rohitkotla/flask-demo'
        CONTAINER_NAME = 'flask-demo'
        APP_PORT = '8080'
        CONTAINER_PORT = '5000'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -eu
                    test -f app.py
                    test -f Dockerfile
                    test -f requirements.txt
                    test -f requirements-ci.txt
                    test -d templates
                    test -d tests
                    echo "Project files validated."
                '''
            }
        }

        stage('Setup CI Environment') {
            steps {
                sh '''
                    set -eu
                    python3 --version
                    python3 -m venv .venv-ci
                    .venv-ci/bin/python -m pip install --upgrade pip
                    .venv-ci/bin/python -m pip install \
                        -r requirements.txt \
                        -r requirements-ci.txt
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    set -eu
                    .venv-ci/bin/python -m pytest -q
                '''
            }
        }

        stage('Code Quality') {
            steps {
                sh '''
                    set -eu
                    .venv-ci/bin/ruff check app.py tests/
                '''
            }
        }

        stage('Dependency Security Audit') {
            steps {
                sh '''
                    set -eu
                    .venv-ci/bin/pip-audit -r requirements.txt
                '''
            }
        }

        stage('Validate Deployment Server') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu
                        ssh -o BatchMode=yes \
                            -o StrictHostKeyChecking=yes \
                            "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "docker --version &&
                             trivy --version &&
                             docker info >/dev/null"
                    '''
                }
            }
        }

        stage('Prepare Remote Directory') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu
                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "mkdir -p '${APP_DIR}'"
                    '''
                }
            }
        }

        stage('Copy Application Files') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        scp app.py Dockerfile requirements.txt \
                            "${DEPLOY_USER}@${DEPLOY_HOST}:${APP_DIR}/"

                        scp -r templates \
                            "${DEPLOY_USER}@${DEPLOY_HOST}:${APP_DIR}/"
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "cd '${APP_DIR}' &&
                             docker build --pull \
                               -t '${DOCKERHUB_REPO}:${BUILD_NUMBER}' \
                               -t '${DOCKERHUB_REPO}:latest' ."
                    '''
                }
            }
        }

        // Generate Trivy JSON report on the Docker server
        // and copy it to the Jenkins workspace.
        stage('Trivy Vulnerability Report') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        IMAGE="${DOCKERHUB_REPO}:${BUILD_NUMBER}"
                        REPORT="trivy-report-${BUILD_NUMBER}.json"

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "trivy image \
                             --scanners vuln \
                             --severity HIGH,CRITICAL \
                             --format json \
                             --output '/tmp/${REPORT}' \
                             '${IMAGE}'"

                        scp "${DEPLOY_USER}@${DEPLOY_HOST}:/tmp/${REPORT}" .
                    '''
                }

                // Convert JSON to a browser-friendly HTML report.
                sh '''
                    set -eu

                    python3 - <<'PY'
import html
import json
import os
from pathlib import Path

build = os.environ["BUILD_NUMBER"]
json_file = Path(f"trivy-report-{build}.json")
report = json.loads(json_file.read_text())

counts = {"CRITICAL": 0, "HIGH": 0}
rows = []

for result in report.get("Results", []):
    for vuln in result.get("Vulnerabilities") or []:
        severity = vuln.get("Severity", "UNKNOWN")

        if severity not in counts:
            continue

        counts[severity] += 1

        values = [
            severity,
            vuln.get("VulnerabilityID", ""),
            vuln.get("PkgName", ""),
            vuln.get("InstalledVersion", ""),
            vuln.get("FixedVersion") or "Not listed",
            vuln.get("Title") or vuln.get("Description") or "",
        ]

        cells = "".join(
            "<td>" + html.escape(str(value)) + "</td>"
            for value in values
        )
        rows.append('<tr class="severity-' + severity.lower() + '">' + cells + "</tr>")

table_rows = "\\n".join(rows)

if not table_rows:
    table_rows = (
        '<tr><td colspan="6">'
        'No HIGH or CRITICAL findings reported.'
        '</td></tr>'
    )

unique_cves = {
    vuln.get("VulnerabilityID")
    for result in report.get("Results", [])
    for vuln in (result.get("Vulnerabilities") or [])
    if vuln.get("VulnerabilityID")
    and vuln.get("Severity") in counts
}

page = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Trivy Security Dashboard</title>
<link rel="stylesheet" href="trivy-report.css">
</head>
<body>
<main class="container">
  <header class="hero">
    <div>
      <div class="eyebrow">Application Security / Container Scan</div>
      <h1>Trivy Security Dashboard</h1>
      <div class="subtitle">Docker image vulnerability assessment · Jenkins build #BUILD_NUMBER</div>
    </div>
    <div class="status">● SCAN SUMMARY</div>
  </header>

  <section class="cards">
    <article class="card high">
      <div class="card-label">High severity</div>
      <div class="number">HIGH_COUNT</div>
      <div class="card-hint">Findings requiring review</div>
    </article>
    <article class="card critical">
      <div class="card-label">Critical severity</div>
      <div class="number">CRITICAL_COUNT</div>
      <div class="card-hint">Highest-priority findings</div>
    </article>
    <article class="card unique">
      <div class="card-label">Unique CVEs</div>
      <div class="number">UNIQUE_COUNT</div>
      <div class="card-hint">Distinct vulnerability IDs</div>
    </article>
    <article class="card total">
      <div class="card-label">Package findings</div>
      <div class="number">TOTAL_COUNT</div>
      <div class="card-hint">Affected package entries</div>
    </article>
  </section>

  <section class="panel">
    <div class="panel-head">
      <div>
        <h2>Vulnerability findings</h2>
        <div class="panel-subtitle">Search CVEs, packages, versions or descriptions</div>
      </div>
      <div class="controls">
        <input id="search" type="search" placeholder="Search findings..." aria-label="Search findings">
        <select id="severity" aria-label="Filter by severity">
          <option value="all">All severities</option>
          <option value="high">High</option>
          <option value="critical">Critical</option>
        </select>
      </div>
    </div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Severity</th><th>CVE</th><th>Package</th>
            <th>Installed version</th><th>Fixed version</th><th>Description</th>
          </tr>
        </thead>
        <tbody id="findings">TABLE_ROWS</tbody>
      </table>
      <div id="empty" class="empty" hidden>No findings match your search.</div>
    </div>
  </section>

  <div class="footer">
    <span>Generated by Trivy · Jenkins build #BUILD_NUMBER</span>
    <span>“Not listed” means Trivy did not provide a fixed version.</span>
  </div>
</main>
<!-- Search/filter disabled for CSP compatibility -->
</body>
</html>
"""

page = (
    page.replace("BUILD_NUMBER", html.escape(build))
        .replace("HIGH_COUNT", str(counts["HIGH"]))
        .replace("CRITICAL_COUNT", str(counts["CRITICAL"]))
        .replace("UNIQUE_COUNT", str(len(unique_cves)))
        .replace("TOTAL_COUNT", str(sum(counts.values())))
        .replace("TABLE_ROWS", table_rows)
)

Path("trivy-report.html").write_text(page)

print("HTML report generated: trivy-report.html")
print("HIGH findings:", counts["HIGH"])
print("CRITICAL findings:", counts["CRITICAL"])
PY
                '''

                // Publish a clickable HTML report on the Jenkins job page.
                publishHTML(target: [
                    reportName: 'Trivy Security Report',
                    reportDir: '.',
                    reportFiles: 'trivy-report.html',
                    keepAll: true,
                    alwaysLinkToLastBuild: true,
                    allowMissing: false
                ])

                archiveArtifacts(
                    artifacts: 'trivy-report-*.json,trivy-report.html,trivy-report.css',
                    fingerprint: true
                )
            }
        }

        stage('Trivy Security Gate') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        IMAGE="${DOCKERHUB_REPO}:${BUILD_NUMBER}"

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "trivy image \
                             --scanners vuln \
                             --ignore-unfixed \
                             --severity HIGH,CRITICAL \
                             --exit-code 1 \
                             '${IMAGE}'"

                        echo "Trivy security gate passed."
                    '''
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'docker-hub-creds',
                            usernameVariable: 'DH_USER',
                            passwordVariable: 'DH_PASS'
                        )
                    ]) {
                        sh '''
                            set -eu

                            printf '%s' "$DH_PASS" |
                                ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                                "docker login \
                                 --username '${DH_USER}' \
                                 --password-stdin &&
                                 docker push '${DOCKERHUB_REPO}:${BUILD_NUMBER}' &&
                                 docker push '${DOCKERHUB_REPO}:latest' &&
                                 docker logout"
                        '''
                    }
                }
            }
        }

        stage('Deploy Application') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        IMAGE="${DOCKERHUB_REPO}:${BUILD_NUMBER}"

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "docker rm -f '${CONTAINER_NAME}' 2>/dev/null || true"

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "docker run -d \
                             --name '${CONTAINER_NAME}' \
                             --restart unless-stopped \
                             -p '${APP_PORT}:${CONTAINER_PORT}' \
                             '${IMAGE}'"
                    '''
                }
            }
        }

        stage('Health Check') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" '
                            for i in $(seq 1 12); do
                                if curl -fsS \
                                    http://127.0.0.1:8080/health; then
                                    echo
                                    echo "Health check passed."
                                    exit 0
                                fi

                                echo "Waiting for application... attempt $i/12"
                                sleep 5
                            done

                            echo "Health check failed."
                            docker logs --tail 100 flask-demo
                            exit 1
                        '
                    '''
                }
            }
        }
    }

    post {
        success {
            echo """
                CI/CD pipeline completed successfully.
                Image: ${DOCKERHUB_REPO}:${BUILD_NUMBER}
                Application: http://${DEPLOY_HOST}:${APP_PORT}
            """
        }

        failure {
            echo """
                CI/CD pipeline failed.
                Check the failed stage and Jenkins console output.
            """
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
