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
        sh 'pwsh Install-DSS.ps1'
      }
    }
  }
}
