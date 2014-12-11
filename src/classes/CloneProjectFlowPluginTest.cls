@isTest
private class CloneProjectFlowPluginTest {
	public static TASKRAY__Project__c parentProject;

	private static void setupTestData(){
		// Create a template TaskRay project
		parentProject = new TASKRAY__Project__c(Name ='Test Project');
		insert parentProject;
		TASKRAY__Project__c subProject = new TASKRAY__Project__c(Name ='Test Sub Project', TASKRAY__Project_Parent__c=parentProject.Id);
		insert subProject;

		//Insert some TaskRay tasks
		List<TASKRAY__Project_Task__c> tasks = new List<TASKRAY__Project_Task__c>();
		for(Integer i=0; i<10; i++){
			tasks.add(new TASKRAY__Project_Task__c(Name ='Test Task '+i, TASKRAY__Project__c=parentProject.Id));
			tasks.add(new TASKRAY__Project_Task__c(Name ='Test Task '+i, TASKRAY__Project__c=subProject.Id));
		}
		insert tasks;

	}

	@isTest static void basicTest() {
		setupTestData();
		
		 // Create test clone
        CloneProjectFlowPlugin clonePlugin = new CloneProjectFlowPlugin();
        Map<String,Object> inputParams = new Map<String,Object>();
        //Map<String,Object> outputParams = new Map<String,Object>();

        inputParams.put('templateProjectId',parentProject.Id);

        Process.PluginRequest request = new Process.PluginRequest(inputParams);
        Process.PluginResult result;
        result = clonePlugin.invoke(request);

        //Now see if we cloned some stuff
        List<TASKRAY__Project__c> projects = [SELECT Id FROM TASKRAY__Project__c];
        system.assertEquals(4,projects.size());
	}

	@isTest static void advancedTest() {
		setupTestData();
		
		 // Create test clone
        CloneProjectFlowPlugin clonePlugin = new CloneProjectFlowPlugin();
        Map<String,Object> inputParams = new Map<String,Object>();

        inputParams.put('templateProjectId',parentProject.Id);
        //Pass a project rename
        inputParams.put('newProjectName','Rename Test');
        //Pass a Project field update
        String projectUpdateJSON='{"TASKRAY__ChatterGroupSharingIds__c":"0F930000000PHBO"}';
        inputParams.put('projectFieldOverridesJSON',projectUpdateJSON);
        String taskUpdateJSON='{"TASKRAY__Priority__c":"High"}';
        inputParams.put('taskFieldOverridesJSON',taskUpdateJSON);

        Process.PluginRequest request = new Process.PluginRequest(inputParams);
        Process.PluginResult result = clonePlugin.invoke(request);
        Map<String,Object> outputParams = result.outputParameters;
        Id newParentProjectId  = (Id)outputParams.get('newParentProjectId');

        //Now see if we cloned some stuff
        List<TASKRAY__Project__c> projects = [SELECT Id,Name,TASKRAY__ChatterGroupSharingIds__c FROM TASKRAY__Project__c WHERE Id=:newParentProjectId OR TASKRAY__Project_Parent__c=:newParentProjectId];
        system.assertEquals(2,projects.size());
        Set<Id> projectIds = new Set<Id>();
        for(TASKRAY__Project__c project : projects){
        	projectIds.add(project.Id);
        	if(project.Id == newParentProjectId){
        		//Assert the rename worked
        		system.assertEquals('Rename Test',project.Name);
        	}
        	//Assert the project field update worked
        	system.assertEquals('0F930000000PHBO',project.TASKRAY__ChatterGroupSharingIds__c);
        }

        List<TASKRAY__Project_Task__c> tasks = [SELECT Id,Name,TASKRAY__Priority__c FROM TASKRAY__Project_Task__c WHERE TASKRAY__Project__c IN :projectIds];
        for(TASKRAY__Project_Task__c task : tasks){
        	system.assertEquals('High',task.TASKRAY__Priority__c);
        }

	}
	
	@isTest static void describeTest() {
        CloneProjectFlowPlugin clonePlugin = new CloneProjectFlowPlugin();
        Process.PluginDescribeResult result = clonePlugin.describe();
        
        System.AssertEquals(result.inputParameters.size(), 4);
        System.AssertEquals(result.outputParameters.size(), 1);
        
    }

    @isTest static void testNoTemplateExceptions(){
    	//Create an Id that is not a project
 		TASKRAY__Project_Task__c notAProject = new TASKRAY__Project_Task__c(Name ='Test Task for id');
 		insert notAProject;
 		CloneProjectFlowPlugin clonePlugin = new CloneProjectFlowPlugin();
        Map<String,Object> inputParams = new Map<String,Object>();
        //Pass the wrong id for the template project id
        inputParams.put('templateProjectId',notAProject.Id);

        Process.PluginRequest request = new Process.PluginRequest(inputParams);
        try{
	    	Process.PluginResult result = clonePlugin.invoke(request);
    	} catch(Exception e){
    		system.assert(e.getMessage().contains('No Project Template'));
    	}
    }

    @isTest static void testProjectJSONExceptions(){
    	setupTestData();
 		CloneProjectFlowPlugin clonePlugin = new CloneProjectFlowPlugin();
        Map<String,Object> inputParams = new Map<String,Object>();
        //Pass the wrong id for the template project id
        inputParams.put('templateProjectId',parentProject.Id);
        //bad JSON, added a [
        String projectUpdateJSON='[{"TASKRAY__ChatterGroupSharingIds__c":"0F930000000PHBO"}';
        inputParams.put('projectFieldOverridesJSON',projectUpdateJSON);

        Process.PluginRequest request = new Process.PluginRequest(inputParams);
        try{
	    	Process.PluginResult result = clonePlugin.invoke(request);
    	} catch(Exception e){
    		system.assert(e.getMessage().contains('Could not parse this JSON'));
    	}
    }

    @isTest static void testTaskJSONExceptions(){
    	setupTestData();
 		CloneProjectFlowPlugin clonePlugin = new CloneProjectFlowPlugin();
        Map<String,Object> inputParams = new Map<String,Object>();
        //Pass the wrong id for the template project id
        inputParams.put('templateProjectId',parentProject.Id);
        //bad JSON, added a [
        String taskUpdateJSON='[{"TASKRAY__Priority__c":"High"}';
        inputParams.put('taskFieldOverridesJSON',taskUpdateJSON);

        Process.PluginRequest request = new Process.PluginRequest(inputParams);
        try{
	    	Process.PluginResult result = clonePlugin.invoke(request);
    	} catch(Exception e){
    		system.assert(e.getMessage().contains('Could not parse this JSON'));
    	}
    }
}