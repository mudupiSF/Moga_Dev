({
  // Client-side function that invokes the subscribe method on the
  // empApi component.
  subscribe: function (component, replayId) {
    var self = this;

    // Get the empApi component.
    const empApi = component.find ('empApi');

    // Get the channel from the attribute.
    const channel = component.get ('v.channel');

    // Get existing subscription
    const subscription = component.get ('v.subscription');

    // Subscription option to get only new events.
    var tmpReplayId = -1;
    if (replayId != null && replayId > -1) {
      console.log ('setting tmpReplayId=' + replayId);
      tmpReplayId = replayId;
    }

    // Callback function to be passed in the subscribe call.
    // After an event is received, this callback prints the event
    // payload to the console. A helper method displays the message
    // in the console app.
    const callback = function (message) {
      console.log ('Event Received : ' + JSON.stringify (message));
      self.onReceiveNotification (component, message);
    };

    if (subscription == null) {
      // Subscribe to the channel and save the returned subscription object.
      empApi.subscribe (channel, tmpReplayId, $A.getCallback (callback)).then (
        $A.getCallback (function (newSubscription) {
          console.log ('Subscribed to channel ' + channel);
          component.set ('v.subscription', newSubscription);
        })
      );
    } else {
      // Unsubscribe from event
      empApi.unsubscribe (
        subscription,
        $A.getCallback (unsubscribed => {
          // Confirm that we have unsubscribed from the event channel
          console.log (
            'Unsubscribed from channel ' + unsubscribed.subscription
          );
          component.set ('v.subscription', null);
          empApi
            .subscribe (channel, tmpReplayId, $A.getCallback (callback))
            .then (
              $A.getCallback (function (newSubscription) {
                console.log ('Subscribed to channel ' + channel);
                component.set ('v.subscription', newSubscription);
              })
            );
        })
      );
    }
  },
  // Invokes the unsubscribe method on the empApi component
  unsubscribe: function (component) {
    // Get the empApi component
    const empApi = component.find ('empApi');
    // Get the subscription that we saved when subscribing
    const subscription = component.get ('v.subscription');

    // Unsubscribe from event
    empApi.unsubscribe (
      subscription,
      $A.getCallback (unsubscribed => {
        // Confirm that we have unsubscribed from the event channel
        console.log ('Unsubscribed from channel ' + unsubscribed.subscription);
        component.set ('v.subscription', null);
      })
    );
  },
  // Client-side function that displays the platform event message
  // in the console app and displays a toast if not muted.
  onReceiveNotification: function (component, message) {
    console.log ('message=' + JSON.stringify (message, null, 2));
    var log = component.get ('v.log');
    if (log != null) {
      log = JSON.stringify (message, null, 2) + '\r\n\r\n' + log;
    } else {
      log = JSON.stringify (message, null, 2);
    }

    component.set ('v.log', log);
    /*
      // Extract notification from platform event
      const newNotification = {
        time: $A.localizationService.formatDateTime(
          message.data.payload.CreatedDate, 'HH:mm'),
        message: message.data.payload.Message__c
      };

      // Save notification in history
      const notifications = component.get('v.notifications');
      notifications.push(newNotification);
      component.set('v.notifications', notifications);

      // Display notification in a toast
      this.displayToast(component, 'info', newNotification.message);
      */
  },
  // Displays the given toast message.
  displayToast: function (component, type, message) {
    const toastEvent = $A.get ('e.force:showToast');
    toastEvent.setParams ({
      type: type,
      message: message,
    });
    toastEvent.fire ();
  },
});