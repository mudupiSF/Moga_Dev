({
  // Called when the component is initialized.
  // Subscribes to the channel and displays a toast message.
  // Specifies an error handler function for empApi
  onInit: function (component, event, helper) {
    component.set ('v.subscription', null);
    //component.set('v.notifications', []);
    // Get empApi component.
    const empApi = component.find ('empApi');
    // Define an error handler function that prints the error to the console.
    const errorHandler = function (message) {
      console.error ('Received error ', JSON.stringify (message));
    };
    // Register empApi error listener and pass in the error handler function.
    empApi.onError ($A.getCallback (errorHandler));
    helper.subscribe (component);
    helper.displayToast (
      component,
      'success',
      'Ready to receive notifications.'
    );
  },
  // Clear notifications in console app.
  handleClear: function (component, event, helper) {
    component.set ('v.log', null);
  },
  handleReplayChange: function (component, event, helper) {
    if (event.which == 13) {
      console.log ('handleReplayChange...');
      console.log ('ReplayId=' + component.get ('v.replayId'));
      component.set ('v.log', null);
      helper.subscribe (component, component.get ('v.replayId'));
    }
  },
  destroyCmp: function (component, event, helper) {
    helper.unsubscribe (component);
  },
});