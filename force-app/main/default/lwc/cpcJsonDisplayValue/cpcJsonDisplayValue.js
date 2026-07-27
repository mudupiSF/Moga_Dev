import { LightningElement, api } from 'lwc';

export default class CpcJsonDisplayValue extends LightningElement {
    @api jsonValue; // JSON string or object
    @api jsonTextNodesToDisplay; // Comma-separated node paths like "Amount__c:Value,Amount__c:Currency"
    
    /**
     * Getter to compute and return the displayed value
     * Parses JSON and extracts values based on node paths
     */
    get displayedValue() {
        if (!this.jsonValue || !this.jsonTextNodesToDisplay) {
            return '';
        }
        
        try {
            // Parse JSON if it's a string
            let jsonData = this.jsonValue;
            if (typeof this.jsonValue === 'string') {
                jsonData = JSON.parse(this.jsonValue);
            }
            
            // Handle array - take first element if it's an array
            if (Array.isArray(jsonData) && jsonData.length > 0) {
                jsonData = jsonData[0];
            }
            
            // Split node paths by comma and filter out empty paths
            const nodePaths = this.jsonTextNodesToDisplay.split(',')
                .map(path => path.trim())
                .filter(path => path.length > 0);
            const values = [];
            
            // Extract values for each node path
            for (const nodePath of nodePaths) {
                const value = this.extractValueFromPath(jsonData, nodePath);
                // Filter out null, undefined, and empty strings
                if (value !== null && value !== undefined && String(value).trim() !== '') {
                    values.push(String(value).trim());
                }
            }
            
            // Join values with space and trim the result
            return values.join(' ').trim();
            
        } catch (error) {
            console.error('Error parsing JSON or extracting values:', error);
            return '';
        }
    }
    
    /**
     * Extract value from JSON object using dot notation path
     * Example: "Amount__c:Value" means jsonData.Amount__c.Value
     * @param {Object} jsonData - The JSON object to traverse
     * @param {String} path - The node path (e.g., "Amount__c:Value")
     * @returns {*} The extracted value or null if not found
     */
    extractValueFromPath(jsonData, path) {
        if (!jsonData || !path) {
            return null;
        }
        
        try {
            // Split path by colon to handle nested paths
            const pathParts = path.split(':').map(part => part.trim());
            
            let current = jsonData;
            for (const part of pathParts) {
                if (current && typeof current === 'object' && part in current) {
                    current = current[part];
                } else {
                    return null;
                }
            }
            
            return current;
        } catch (error) {
            console.error('Error extracting value from path:', path, error);
            return null;
        }
    }
}