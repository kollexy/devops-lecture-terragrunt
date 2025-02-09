# ---------------------------------------------------------------------------------------------------------------------
# CI/CD PIPELINE FOR THE INFRASTRUCTURE OF HDFPORTAL
#
# This pipeline contains 3 stages:
# 1. Init   - Initialize terraform remote state
# 2. Plan   - Validate and plan the infrastructure
# 3. Deploy - Apply the changes to the infrastructure
# ---------------------------------------------------------------------------------------------------------------------

pool:
  vmImage: 'ubuntu-latest'
variables:
  - group: terraform-dev

stages:

# ---------------------------------------------------------------------------------------------------------------------
# Initalization stage
#
# Initialize a resource group with a storage account and a container that will be used as remote state.
# Terraform needs to store it's state somewhere to keep track of the infrastructure, with this stage we ensure that
# the remote state will be created.
# ---------------------------------------------------------------------------------------------------------------------

- stage: Init
  jobs:
  - job: InitRemoteState
    steps:    
    - script: |
        chmod +x ./scripts/terraform-init-remote-state.sh
      displayName: 'Enable script permissions'

    - task: Bash@3
      inputs:
        filePath: './scripts/terraform-init-remote-state.sh'
      displayName: 'Init remote state'

# ---------------------------------------------------------------------------------------------------------------------
# Plan stage
#
# In this stage we are performing validation and creating the plan for the infrastrucure, but before we can do that we
# first need to download terragrunt.
# ---------------------------------------------------------------------------------------------------------------------

- stage: Plan
  dependsOn: Init
  jobs:
  - job: Plan
    steps:
    - template: download-terragrunt.yaml

    - script: terragrunt run-all validate --terragrunt-working-dir live/
      displayName: 'Run terragrunt run-all validate'

    - script: chmod +x ./scripts/terragrunt-plan.sh
      displayName: 'Enable script permissions'

    - task: Bash@3
      inputs:
        filePath: './scripts/terragrunt-plan.sh'
        arguments: 'plan.log'
      displayName: 'Run terragrunt plan-all'

    - task: CopyFiles@2
      inputs:
        contents: 'plan.log'
        targetFolder: $(Build.ArtifactStagingDirectory)
      displayName: 'Copy plan to artifact staging directory'

    - task: PublishPipelineArtifact@0
      inputs:
        targetPath: '$(Build.ArtifactStagingDirectory)'
        ArtifactName: 'Plan'
      displayName: 'Publish Plan Artifact'



# ---------------------------------------------------------------------------------------------------------------------
# Apply stage
#
# In this stage we are applying/deplyoing our changes to the infrastructure. 
# This stage will only run on the master and develop branches and needs a manual approval.
# Similarly to the Plan stage we first need to download terragrunt. After that we apply our
# changes by calling terragrunt apply-all.
# ---------------------------------------------------------------------------------------------------------------------

- stage: Apply
  dependsOn: Plan
  condition: and(succeeded(), in(variables['Build.SourceBranch'], 'refs/heads/master', 'refs/heads/develop'))
  variables:
    ${{ if eq(variables['Build.SourceBranch'], 'refs/heads/master') }}:
      environment: 'dev'
    ${{ if ne(variables['Build.SourceBranch'], 'refs/heads/master') }}:
      environment: 'dev'
  jobs:
    - deployment: DeployInfrastructure
      environment: ${{ variables.environment }}
      strategy:
        runOnce:
          deploy:
            steps:
            - download: none
            - checkout: self

            - template: download-terragrunt.yaml

            - script: chmod +x ./scripts/terragrunt-apply.sh
              displayName: 'Enable script permissions'

            - task: Bash@3
              inputs:
                filePath: './scripts/terragrunt-apply.sh'
                arguments: 'apply.log'
              displayName: 'Run terragrunt apply-all'
            
            - task: CopyFiles@2
              inputs:
                contents: 'apply.log'
                targetFolder: $(Build.ArtifactStagingDirectory)
              displayName: 'Copy apply output to artifact staging directory'
        
            - task: PublishPipelineArtifact@0
              inputs:
                targetPath: '$(Build.ArtifactStagingDirectory)'
                ArtifactName: 'Apply'
              displayName: 'Publish apply artifact'
