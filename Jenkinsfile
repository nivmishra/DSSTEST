pipeline {
  agent any
  stages {
    stage('version') {
      steps {
        sh 'pwsh --version'
      }
    }
    stage('hello') {
      steps {
        sh 'pwsh /Invoke-BackupSSASDbs.ps1'
      }
    }
  }
}
