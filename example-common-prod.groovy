import groovy.json.JsonSlurper
import java.nio.file.Files
import java.nio.file.Paths
pipeline{
    agent any
    post{
        success{
            script{
                sh "echo ${imageRepo} "
            }
        }
        failure{
            script{
                sh "echo 'failure'"
            }
        }
        aborted{
            script{
                sh "echo 'aborted'"
            }
        }
    always {
            cleanWs()
        }
    }
    options {
        // build history
        buildDiscarder(logRotator(numToKeepStr: "5",daysToKeepStr: "15"))
      timestamps()
      timeout(time: 30, unit:'MINUTES')
    }
//  parameters {
//        string(name: "branch", defaultValue: "test_1.3.0", description: "choose branch")
//    }
    environment {
        confFile = "example/example-conf-prod.json"
    }
    stages {
        stage("Get variables") {
             steps {
                script {
                    // init vars
                    env.extraBuildParams = ""
                    env.namespace = JOB_NAME.split('_')[-1]
                    env.project = JOB_NAME.split('_')[0]
                    env.imageTag = new Date().format("yyyyMMddHHmm")
                    // read json file
                    def readJsonFile = { filePath ->
                        def jsonText = readFile(filePath)
                        return new groovy.json.JsonSlurper().parseText(jsonText)
                    }
                    def projectDict = readJsonFile(confFile)
                    def getValue = { json, key ->
                        return json[project]?.get(key) ?: json?.global?.get(key) ?: ""  // get the values, default ""
                    }
                    env.gitCredentialsId = getValue(projectDict,"gitCredentialsId")
                    env.imageUrl = getValue(projectDict,"imageUrl")
                    env.buildParams = getValue(projectDict,"buildParams")
                    env.imageRepo = "${imageUrl}/${namespace}/${JOB_NAME}:${imageTag}"
                    env.k8sServer = getValue(projectDict,"k8sServer")
                    env.gitUrl = getValue(projectDict,"gitUrl")
                    env.buildParams = getValue(projectDict,"buildParams")
                    env.packagePath = getValue(projectDict,"packagePath")
                    env.uploadFlag = getValue(projectDict,"uploadFlag")
                    env.kubeCredentialsId = getValue(projectDict,"kubeCredentialsId")
                    env.ingressTag = getValue(projectDict,"ingressTag")
                    extraBuildTag = getValue(projectDict,"extraBuildTag")
                    if (extraBuildTag == "true") {
                        env.extraBuildParams = "-Dcompile.version=${env.namespace}"
                    }
                    if (uploadFlag == "true") {
                        env.nexusUrl = getValue(projectDict,"nexusUrl")
                        env.nexusRepository = getValue(projectDict,"nexusRepository")
                        env.nexusCredentialsId = getValue(projectDict,"nexusCredentialsId")
                        env.protocol = getValue(projectDict,"protocol")
                        env.artifactId = getValue(projectDict,"artifactId")
                        env.uploadPath = getValue(projectDict,"uploadPath")
                        env.nexusGroupId= getValue(projectDict,"nexusGroupId")
                    }

                }
             }
        }
        stage("Pull code") {
            steps {
                checkout scmGit(branches: [[name: "${branch}"]], extensions: [],
                userRemoteConfigs: [[credentialsId: "${gitCredentialsId}",
                url: "${gitUrl}"]])
            }
        }
        stage("Code build") {
            steps {
                sh """
                    ${buildParams} ${extraBuildParams}
                """
            }
        }
        stage("Depend on upload"){
           when {
                environment name: 'uploadFlag', value: 'true'
           }
           steps {
             nexusArtifactUploader(
                nexusVersion: 'nexus3',
                protocol: "${protocol}",
                nexusUrl: "${nexusUrl}",
                groupId: "${nexusGroupId}",
                version: "1.0-${namespace}-SNAPSHOT",
                repository: "${nexusRepository}",
                credentialsId: "${nexusCredentialsId}",
                artifacts: [
                    [
                        artifactId: "${artifactId}",
                        classifier: "",
                        file: "${uploadPath}/app.jar",
                        type: "jar"
                    ]
                ]
             )
            }
        }
      
        stage("Image build") {
            steps {
                withCredentials([usernamePassword(credentialsId: 'harbor', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS')]) {
                        sh "docker login  ${imageUrl} -u ${HARBOR_USER} -p ${HARBOR_PASS}"
                    }
                sh """
                    cd ${packagePath}
                    docker build -t ${imageRepo} .
                    docker push ${imageRepo}
                    docker rmi ${imageRepo}
                """
            }
        }
        stage("K8s deploy"){
            steps {
                withKubeConfig(credentialsId: "${kubeCredentialsId}", serverUrl: "${k8sServer}") {
                sh """
                kubectl set image deployment/${project} ${project}=${imageUrl}/${namespace}/$JOB_NAME:${imageTag} -n ${namespace}
                """
                }
            }
        }
    }
}
