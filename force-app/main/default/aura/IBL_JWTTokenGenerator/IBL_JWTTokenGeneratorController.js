({
    // JWT Token Generation
	generate : function(component, event, helper)
    {
        component.set("v.showSpinner", true);
        component.set("v.message", null);
        var action = component.get("c.fetchToken");
		
        action.setParams({
			"personaName" : component.get("v.personaName")
        });
        
        action.setCallback(this,function(data){
            component.set("v.showSpinner", false);
            
            //get the response state
            var state = data.getState();
            // get return value from controller
            var output = data.getReturnValue();
            //console.log("output**"+JSON.stringify(output));
            
            //check if result is successful
            if(state == "SUCCESS")
            {
                if(output)
                {
					component.set("v.pageTitle","TOKEN DETAILS");
                    component.set("v.myWrap",output);
					component.set("v.message",output.sfErrMsg);
					component.set("v.isJWTGenerated",output.jwtSignedAndVerified);
                }
            } 
            else if(state == "ERROR"){
				component.set("v.message","token generation error, please contact your administrator");
                console.log('Exception'+output);
            }
        });
        $A.enqueueAction(action);        
    },
    
	clearData : function(component, event, helper){
        component.set("v.pageTitle","METADATA DETAILS");
		component.set("v.personaName","");
		component.set("v.isJWTGenerated",false);
		component.set("v.message",null);
	},
    
	SearchAgain : function(component, event, helper){
        component.set("v.pageTitle","METADATA DETAILS");
		component.set("v.isJWTGenerated",false);
		component.set("v.message",null);
	},
    
    // Mode Selection
    selectMode : function(component, event, helper){
        var selectedMode = event.getSource().get("v.value");
        component.set("v.selectedMode", selectedMode);
        
        // Reset states
        component.set("v.isProcessed", false);
        component.set("v.inputJSON", "");
        component.set("v.outputResult", "");
        component.set("v.message", null);
        
        // Update page title based on mode
        if(selectedMode === "JWT"){
            component.set("v.pageTitle", "METADATA DETAILS");
        } else if(selectedMode === "ENCRYPT"){
            component.set("v.pageTitle", "ENCRYPTION UTILITY");
        } else if(selectedMode === "DECRYPT"){
            component.set("v.pageTitle", "DECRYPTION UTILITY");
        }
    },
    
    // Encryption
    encryptData : function(component, event, helper){
        var inputJSON = component.get("v.inputJSON");
        
        if(!inputJSON || inputJSON.trim() === ""){
            component.set("v.message", "Please enter JSON to encrypt");
            return;
        }
        
        component.set("v.showSpinner", true);
        component.set("v.message", null);
        
        var action = component.get("c.encryptJSON");
        action.setParams({
            "plainJSON" : inputJSON
        });
        
        action.setCallback(this, function(response){
            component.set("v.showSpinner", false);
            var state = response.getState();
            
            if(state === "SUCCESS"){
                var result = response.getReturnValue();
                
                // Format the encrypted JSON in pretty format
                var formattedResult = result;
                try {
                    var jsonObj = JSON.parse(result);
                    formattedResult = JSON.stringify(jsonObj, null, 4);
                } catch(e) {
                    formattedResult = result;
                }
                
                component.set("v.outputResult", formattedResult);
                component.set("v.isProcessed", true);
                component.set("v.pageTitle", "ENCRYPTION RESULT");
            } else if(state === "ERROR"){
                var errors = response.getError();
                var message = 'Unknown error';
                if (errors && errors[0] && errors[0].message) {
                    message = errors[0].message;
                }
                component.set("v.message", message);
            }
        });
        
        $A.enqueueAction(action);
    },
    
    resetEncryption : function(component, event, helper){
        component.set("v.inputJSON", "");
        component.set("v.outputResult", "");
        component.set("v.isProcessed", false);
        component.set("v.message", null);
        component.set("v.pageTitle", "ENCRYPTION UTILITY");
    },
    
    // Decryption
    decryptData : function(component, event, helper){
        var inputJSON = component.get("v.inputJSON");
        
        if(!inputJSON || inputJSON.trim() === ""){
            component.set("v.message", "Please enter encrypted data to decrypt");
            return;
        }
        
        // Minify/compact the input JSON by removing all whitespace
        var compactedJSON = helper.compactJSON(inputJSON);
        
        component.set("v.showSpinner", true);
        component.set("v.message", null);
        
        var action = component.get("c.decryptJSON");
        action.setParams({
            "encryptedJSON" : compactedJSON
        });
        
        action.setCallback(this, function(response){
            component.set("v.showSpinner", false);
            var state = response.getState();
            
            if(state === "SUCCESS"){
                var result = response.getReturnValue();
                
                var formattedResult = result;
                try {
                    var jsonObj = JSON.parse(result);
                    formattedResult = JSON.stringify(jsonObj, null, 2);
                } catch(e) {
                    formattedResult = result;
                }
                
                component.set("v.outputResult", formattedResult);
                component.set("v.isProcessed", true);
                component.set("v.pageTitle", "DECRYPTION RESULT");
            } else if(state === "ERROR"){
                var errors = response.getError();
                var message = 'Unknown error';
                if (errors && errors[0] && errors[0].message) {
                    message = errors[0].message;
                }
                component.set("v.message", message);
            }
        });
        
        $A.enqueueAction(action);
    },
    
    resetDecryption : function(component, event, helper){
        component.set("v.inputJSON", "");
        component.set("v.outputResult", "");
        component.set("v.isProcessed", false);
        component.set("v.message", null);
        component.set("v.pageTitle", "DECRYPTION UTILITY");
    },
    
    // Copy Functions
    copyJWTToken : function(component, event, helper){
        var jwtToken = component.get("v.myWrap.jwtToken");
        helper.copyToClipboard(jwtToken);
        helper.showToast("Success", "JWT Token copied to clipboard!", "success");
    },
    
    copyAccessToken : function(component, event, helper){
        var accessToken = component.get("v.myWrap.access_token");
        helper.copyToClipboard(accessToken);
        helper.showToast("Success", "Access Token copied to clipboard!", "success");
    },
    
    copyResult : function(component, event, helper){
        var result = component.get("v.outputResult");
        
        var selectedMode = component.get("v.selectedMode");
        var copyText = result;
        
        if(selectedMode === "DECRYPT"){
            try {
                
                var jsonObj = JSON.parse(result);
                copyText = JSON.stringify(jsonObj);
            } catch(e) {
                copyText = result;
            }
        }
        
        helper.copyToClipboard(copyText);
        helper.showToast("Success", "Result copied to clipboard!", "success");
	}	
});