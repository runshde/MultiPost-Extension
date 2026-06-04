import "~style.css";
import cssText from "data-text:~style.css";
import { HeroUIProvider, Tab, Tabs } from "@heroui/react";
import type { PlasmoCSConfig } from "plasmo";
import ArticleTab from "~components/Sync/ArticleTab";
import DynamicTab from "~components/Sync/DynamicTab";
import SettingsTab from "~components/Sync/SettingsTab";
import VideoTab from "~components/Sync/VideoTab";
import type { SyncData } from "~sync/common";

export const config: PlasmoCSConfig = {};

export function getShadowContainer() {
  return document.querySelector("#test-shadow").shadowRoot.querySelector("#plasmo-shadow-container");
}

export const getShadowHostId = () => "test-shadow";

export const getStyle = () => {
  const style = document.createElement("style");
  style.textContent = cssText;
  return style;
};

const funcPublish = (data: SyncData) => {
  chrome.runtime.sendMessage({ action: "MULTIPOST_EXTENSION_PUBLISH", data });
};

const funcScraper = async (url: string): Promise<unknown> => {
  return new Promise((resolve, reject) => {
    chrome.tabs.create({ url, active: false }, (tab) => {
      const tabId = tab.id;
      if (!tabId) {
        reject(new Error("Failed to create tab"));
        return;
      }

      const timeoutId = setTimeout(() => {
        chrome.tabs.onUpdated.removeListener(onUpdated);
        chrome.tabs.remove(tabId);
        reject(new Error("Scraper timeout"));
      }, 30000);

      const onUpdated = (updatedTabId: number, changeInfo: chrome.tabs.TabChangeInfo) => {
        if (updatedTabId === tabId && changeInfo.status === "complete") {
          chrome.tabs.onUpdated.removeListener(onUpdated);
          setTimeout(() => {
            chrome.tabs.sendMessage(tabId, { type: "MULTIPOST_EXTENSION_REQUEST_SCRAPER_START" }, (response) => {
              clearTimeout(timeoutId);
              chrome.tabs.remove(tabId);
              if (chrome.runtime.lastError) {
                reject(chrome.runtime.lastError);
              } else {
                resolve(response);
              }
            });
          }, 500);
        }
      };

      chrome.tabs.onUpdated.addListener(onUpdated);
    });
  });
};

const Options = () => {
  return (
    <HeroUIProvider>
      <div className="min-h-screen bg-background p-6">
        <div className="max-w-5xl mx-auto">
          <h1 className="text-2xl font-bold mb-6 text-foreground">{chrome.i18n.getMessage("extensionDisplayName")}</h1>
          <Tabs aria-label="publish tabs" variant="underlined" color="primary">
            <Tab key="dynamic" title={chrome.i18n.getMessage("optionsDynamicTab") || "动态"}>
              <div className="py-4">
                <DynamicTab funcPublish={funcPublish} />
              </div>
            </Tab>
            <Tab key="article" title={chrome.i18n.getMessage("optionsArticleTab") || "文章"}>
              <div className="py-4">
                <ArticleTab funcPublish={funcPublish} funcScraper={funcScraper} />
              </div>
            </Tab>
            <Tab key="video" title={chrome.i18n.getMessage("optionsVideoTab") || "视频"}>
              <div className="py-4">
                <VideoTab funcPublish={funcPublish} />
              </div>
            </Tab>
            <Tab key="settings" title={chrome.i18n.getMessage("optionsSettingsTab") || "设置"}>
              <div className="py-4">
                <SettingsTab />
              </div>
            </Tab>
          </Tabs>
        </div>
      </div>
    </HeroUIProvider>
  );
};

export default Options;
