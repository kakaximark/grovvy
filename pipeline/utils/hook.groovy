def cloneCore(args = [:]) {
  def path = args.path ?: '.'
  def git_repo = args.git
  def git_branch = args.branch ?: "dev"
  dir("${path}") {
    checkout scmGit(
      branches: [[name: "$git_branch"]],
      userRemoteConfigs: [[credentialsId: env.GIT_CREDNTIAL, url: "${git_repo}"]]
    )
  }
}

def resolveVars(str) {
  str
    .replaceAll(/\$\{env\.([A-Za-z0-9_]+)\}/) { _, key -> env.get(key) ?: '' }
    .replaceAll(/\$\{params\.([A-Za-z0-9_]+)\}/) { _, key -> params.get(key) ?: '' }
}

def installPNpmDependencies(args = [:]) {
  sh '''
    npm install pnpm@8.6.9 -g && \
    pnpm add vite-plugin-ejs -D \
    pnpm add vue-i18n@latest @intlify/shared@latest @intlify/unplugin-vue-i18n@latest -D \
    pnpm install --lockfile=false
  '''
}

def uploadNexusArtifactUploader(args = [:]) {
  def file = args.file ?: '.'
  def artifact_id = args.artifact_id ?: ''
  def group = args.group ?: ''
  def subfix = args.subfix ?: ''
  if (env.UPLOAD_FLAG) {
    nexusArtifactUploader artifacts:
    [[artifactId: "${artifact_id}", classifier: '',
    file: "${env.ROOT_WORKSPACE}/${env.MAIN_PROJECT}/${file}", type: 'jar']],
    credentialsId: "${env.MAVEN_CREDENTIAL}", groupId: "${group}",
    nexusUrl: 'maven.nexus58.com', nexusVersion: 'nexus3',
    protocol: 'https', repository: 'maven-snapshots',
    version: "${subfix}"
  }
}

def buildGraphNode(args = [:]) {
  def image = args.image ?: ''
  cmd = "docker tag graph-node ${image}:${env.CURRENT_COMMIT_ID?.trim()} && docker push ${image}:${env.CURRENT_COMMIT_ID?.trim()}"
  sh "${cmd}"
  
}

return this as Script
