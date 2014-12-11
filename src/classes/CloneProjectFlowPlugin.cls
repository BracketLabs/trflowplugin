global with sharing class CloneProjectFlowPlugin implements Process.Plugin {
    global Process.PluginResult invoke(Process.PluginRequest request) {
            
        //On invoke assign some variables to pass to the method doing the work

        String templateProjectId = (String)request.inputParameters.get('templateProjectId');
        String newProjectName = (String)request.inputParameters.get('newProjectName');
        String taskFieldOverridesJSON = (String)request.inputParameters.get('taskFieldOverridesJSON');
        String projectFieldOverridesJSON = (String)request.inputParameters.get('projectFieldOverridesJSON');   
        // Clone the project by passing it to a helper method
        Map<String,Object> result = new Map<String,Object>();
        result = cloneProject(templateProjectId, newProjectName, taskFieldOverridesJSON, projectFieldOverridesJSON);
        return new Process.PluginResult(result); 
    }

    // This method describes the plugin's inputs and outputs. It's used by the flow designer
    global Process.PluginDescribeResult describe() {
        // Set up plugin metadata
        Process.PluginDescribeResult result = new Process.PluginDescribeResult();
        result.description = 'The TaskRay template project clone plugin will take a template TaskRay project id, and create a clone of that project.';
        result.tag = 'TaskRay';

        result.inputParameters = new 
            List<Process.PluginDescribeResult.InputParameter>{
            // Template Project Id (mandatory)
            new Process.PluginDescribeResult.InputParameter(
                'templateProjectId', 
                Process.PluginDescribeResult.ParameterType.STRING, 
                true),
            // New Project Name (optional)                
            new Process.PluginDescribeResult.InputParameter(
                'newProjectName', 
                Process.PluginDescribeResult.ParameterType.STRING, 
                false),
            // Project Override JSON String (optional)
            new Process.PluginDescribeResult.InputParameter(
                'projectFieldOverridesJSON', 
                Process.PluginDescribeResult.ParameterType.STRING, 
                false),
            // Task Override JSON String (optional)
            new Process.PluginDescribeResult.InputParameter(
                'taskFieldOverridesJSON', 
                Process.PluginDescribeResult.ParameterType.STRING, 
                false)                                         
        };

        // Create a list that stores output parameters sent 
        // to the flow.
        result.outputParameters = new List<
            Process.PluginDescribeResult.OutputParameter>{
            //Id of the newly created parent project
            new Process.PluginDescribeResult.OutputParameter(
                'newParentProjectId', 
                Process.PluginDescribeResult.ParameterType.STRING)
        };

        return result;
    }
    
    //This method will handle the cloning of our project, utilizing the TaskRay global clone method
    //Documented at: http://taskray.uservoice.com/knowledgebase/articles/448214-using-the-taskray-project-clone-method-in-your-own
    public Map<String,String> cloneProject (String templateProjectId,String newProjectName, String taskFieldOverridesJSON, String projectFieldOverridesJSON) {
        
        Map<String,String> result = new Map<String,String>();

        //If the template id is null, throw an exception
        if (templateProjectId == null) throw new CloneProjectPluginException('Template Project Id cannot be null');
        
        //Make sure we have a project to clone from
        TASKRAY__Project__c[] projects = [SELECT Id,Name FROM TASKRAY__Project__c WHERE Id = :templateProjectId];
        if (projects.size() > 0) {
            //This will be our template project, we will clone from this
            TASKRAY__Project__c templateProject = projects[0];
            
            //We have to create an initial map of new project information, this can be extended in a manner documented at the uservoice.com url above
            Map<String,Map<String,String>> projectInfoMap = new Map<String,Map<String,String>>();
            Map<String,String> cloneInfo = new Map<String,String>();
            if(newProjectName!=null){
                cloneInfo.put('newName', newProjectName);
            } else{
                cloneInfo.put('newName', 'Copy of '+templateProject.Name);
            }
            projectInfoMap.put(templateProjectId,cloneInfo);

            //These are some global clone methods
            Map<String,String> options = new Map<String,String>();
            options.put('cloneChildrenProjects','true');
            options.put('assignInactiveToCurrent','true');

            //Now run the TaskRay clone method
            Id newProjectId = TASKRAY.trTaskBoardController.cloneProjectReturnId_v3(templateProjectId, projectInfoMap, options);
            
            //If we want to update some fields on our newly created records we have to do some more work
            if(taskFieldOverridesJSON!=null || projectFieldOverridesJSON!=null){
                
                Set<Id> projectIdsInTree = new Set<Id>();
                projectIdsInTree.add(newProjectId);
                Set<TASKRAY__Project__c> projectsInTree = new Set<TASKRAY__Project__c>();
                //Now we have to find all the projects we just created, unfortunately this involves traversing the tree several times using a SOQL query to get down to 6 layers
                for(Integer i = 0; i<6 ; i++){
                    List<TASKRAY__Project__c> children = [SELECT Id, TASKRAY__Project_Parent__c FROM TASKRAY__Project__c WHERE TASKRAY__Project_Parent__c IN :projectIdsInTree OR Id = :newProjectId];
                    if(children.size()>0){
                        for(TASKRAY__Project__c child : children){
                            projectIdsInTree.add(child.Id);
                            projectsInTree.add(child);
                        }
                    }
                }
                //If we have project field updates to apply, apply them
                if(projectFieldOverridesJSON!=null){
                    Map<String,Object> projectFieldOverrideMap = new Map<String,Object>();
                    //Throw an exception if we can't parse the json fed to this method
                    try{
                        projectFieldOverrideMap = (Map<String,Object>)JSON.deserializeUntyped(projectFieldOverridesJSON);
                    } catch(Exception e){
                        throw new CloneProjectPluginException('Could not parse this JSON: '+projectFieldOverridesJSON);
                    }
                    //Applying the updates to project fields
                    for(TASKRAY__Project__c project : projectsInTree){
                        for(String fieldName: projectFieldOverrideMap.keySet()){
                            project.put(fieldName,projectFieldOverrideMap.get(fieldName));
                        }
                    }
                    List<TASKRAY__Project__c> projectsForUpdate = new List<TASKRAY__Project__c>(projectsInTree);
                    system.debug(JSON.serialize(projectsForUpdate));
                    update projectsForUpdate;
                }

                //Now we have to find the tasks if we have task overrides to apply
                if(taskFieldOverridesJSON!=null){
                    List<TASKRAY__Project_Task__c> tasks = [SELECT Id FROM TASKRAY__Project_Task__c WHERE TASKRAY__Project__c IN :projectIdsInTree];
                    Map<String,Object> taskFieldOverrideMap = new Map<String,Object>();
                    //Throw an exception if we can't parse the json fed to this method
                    try{
                        taskFieldOverrideMap = (Map<String,Object>)JSON.deserializeUntyped(taskFieldOverridesJSON);
                    } catch(Exception e){
                        throw new CloneProjectPluginException('Could not parse this JSON: '+taskFieldOverridesJSON);
                    }
                    //Applying the updates to task fields
                    for(TASKRAY__Project_Task__c task : tasks){
                        for(String fieldName: taskFieldOverrideMap.keySet()){
                            task.put(fieldName,taskFieldOverrideMap.get(fieldName));
                        }
                    }
                    update tasks;
                }
            }
            //We will return the newly created parent project id to the flow
            result.put('newParentProjectId',newProjectId);
        } else { 
            //If we don't have a template, throw an exception
            throw new CloneProjectPluginException('No Project Template found with Id : "' + templateProjectId + '"');
        }
        return result;
    }
        
    // Utility exception class
    class CloneProjectPluginException extends Exception {}
}