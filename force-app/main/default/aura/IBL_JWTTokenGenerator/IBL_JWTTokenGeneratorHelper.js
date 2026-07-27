({
    copyToClipboard : function(text) {
        // Create a temporary textarea element
        var tempTextArea = document.createElement('textarea');
        tempTextArea.value = text;
        tempTextArea.style.position = 'fixed';
        tempTextArea.style.top = '-9999px';
        tempTextArea.style.left = '-9999px';
        document.body.appendChild(tempTextArea);
        
        // Select and copy the text
        tempTextArea.select();
        tempTextArea.setSelectionRange(0, 99999); // For mobile devices
        
        try {
            document.execCommand('copy');
        } catch (err) {
            console.error('Failed to copy text: ', err);
        }
        
        // Remove the temporary element
        document.body.removeChild(tempTextArea);
    },
    
    showToast : function(title, message, type) {
        var toastEvent = $A.get("e.force:showToast");
        if(toastEvent){
            toastEvent.setParams({
                "title": title,
                "message": message,
                "type": type,
                "duration": 3000
            });
            toastEvent.fire();
        } else {
            // Fallback for non-Lightning Experience
            alert(title + ': ' + message);
        }
    },
    
    compactJSON : function(inputJSON) {
        if(!inputJSON) {
            return inputJSON;
        }
        
        var compacted = inputJSON.replace(/\s+/g, '');
        
        try {
            var jsonObj = JSON.parse(compacted);
            compacted = JSON.stringify(jsonObj);
        } catch(e) {
            
        }
        
        return compacted;
    }
})