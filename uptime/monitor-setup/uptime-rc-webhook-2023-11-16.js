/**
 * Webhook script for uptime.com notifications integration - updated as of 2023-11-16
 * Usage on uptime.com webhook integration setup:
 * put the following in the Custom HTTP Headers to tag ppl in the message
 * contactusers: @<user1_rocketchat_account> @<user2_rocketchat_account> ... ,
 * 
 * see ./sample-uptime-notification-payload.log for what to expect from uptime.com!
 */

/* globals console, _, s */
const USERNAME = 'Uptime.com Alerts';
const AVATAR_URL = 'https://avatars.githubusercontent.com/u/54849620?s=200&v=4';

/* exported Script */
class Script {
  /**
   * @params {object} request
   */
  process_incoming_request({ request }) {
    const data = request.content;
    const checkName = data.check_full_name;
    const checkURL = data.site_url;
    const isUp = data.state_is_up;
    // We are using Custom HTTP Headers to add user tagging information:
    const contactUser = request.headers.contactusers;

    let attachmentColor = `#A63636`;
    let statusText = `DOWN`;
    if (isUp) {
      attachmentColor = `#36A64F`;
      statusText = `UP`;
    }

    let attachmentText = '';
    let titleText = '';
    let titleLink = '';
    if (isUp) {
      attachmentText += 'Back to normal now!';
      titleText = 'More info';
      titleLink = 'https://uptime.com';
    } else {
      attachmentText += `Reason: ${data.output}`;
      titleText = 'More info';
      titleLink = data.alert_history_url;
    }

    return {
      content:{
        alias: USERNAME,
        icon_url: AVATAR_URL,
        text: `${contactUser} Monitor ${checkName} is ${statusText}.\n Link: ${checkURL}\n`,
        attachments: [{
          title: titleText,
          text: attachmentText,
          color: attachmentColor
        }]
      }
    };
  }
}
