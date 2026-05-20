import { Storage } from "@plasmohq/storage";

const _storage = new Storage({ area: "local" });

export const linkExtensionMessageHandler = async (request, _sender, sendResponse) => {
  if (request.action === "MULTIPOST_EXTENSION_LINK_EXTENSION") {
    const params = {
      action: "MULTIPOST_EXTENSION_LINK_EXTENSION",
      apiKey: request.data.apiKey,
    };

    const encodedParams = btoa(JSON.stringify(params));

    chrome.windows.create({
      url: chrome.runtime.getURL(`tabs/link-extension.html#${encodedParams}`),
      type: "popup",
      width: 800,
      height: 600,
    });

    const linkExtensionListener = (message, _authSender, authSendResponse) => {
      if (message.type === "MULTIPOST_EXTENSION_LINK_EXTENSION_CONFIRM") {
        const { confirm } = message;
        sendResponse({ confirm });
        authSendResponse("success");
        chrome.runtime.onMessage.removeListener(linkExtensionListener);
      }
    };
    chrome.runtime.onMessage.addListener(linkExtensionListener);
  }
};
