/**
 * uptime-rc-webhook.js
 * Add Uptime.com notifications via WebHook in Rocket.Chat
 * Usage on uptime.com webhook integration setup: put this in the Custom HTTP Headers to tag ppl in the message`contactusers: @<user1_rocketchat_account> @<user2_rocketchat_account> ... ,`
 */

/* globals console, _, s */
const USERNAME = 'Uptime.com Alerts';
const AVATAR_URL = 'https://avatars.githubusercontent.com/u/54849620?s=200&v=4';

  const time = (totalSeconds) => {
  const seconds = Math.floor(totalSeconds % 60);
  const totalMinutes = Math.floor(totalSeconds / 60);
  const minutes = totalMinutes % 60;
  const totalHours = Math.floor(totalMinutes / 60);
  const hours = totalHours % 24;
  const days = Math.floor(totalHours / 24);

  return `${days}d:${hours}h:${minutes}m:${seconds}s`;
}

/* exported Script */
  class Script {
  /**
   * @params {object} request
   */
    process_incoming_request({ request }) {
    const data = request.content.data;
    // We are using Custom HTTP Headers to add user tagging information:
    const contactUser = request.headers.contactusers;

    let attachmentColor = `#A63636`;
    let statusText = `DOWN`;
    let isUp = data.alert.is_up;
    if (isUp) {
     attachmentColor = `#36A64F`;
     statusText = `UP`;
    }

    let attachmentText = '';
    let titleText = '';
    let titleLink = '';
    if (isUp) {
      const durationString = time(data.downtime.duration);
      attachmentText += `Back to normal now! Was down for ${durationString}`;
      titleText = 'More info';
      titleLink = 'https://uptime.com';
    } else {
      attachmentText += `Reason: ${data.alert.short_output}`;
      titleText = 'More info';
      titleLink = data.links.alert_details;
    }

    return {
     content:{
	    alias: USERNAME,
	    icon_url: AVATAR_URL,
	    text: `${contactUser} Monitor ${data.service.name} is ${statusText}.\n Link: ${data.account.site_url}\n`,
	    attachments: [{
	     title: titleText,
	     title_link: titleLink,
	     text: attachmentText,
	     color: attachmentColor
	    }]
     }
   };
  }
}
