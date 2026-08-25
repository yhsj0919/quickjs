declare module 'quickjs_ui/webview' {
  import type { JsUiEvent, JsUiNode } from 'quickjs_ui';

  export type WebCookie = {
    name: string;
    value: string;
    domain: string;
    path?: string;
  };

  export type DomRule = {
    find(selector: string): DomRule;
    children(selector: string): DomRule;
    first(): DomRule;
    last(): DomRule;
    at(index: number): DomRule;
    text(value: string): DomRule;
    html(value: string): DomRule;
    replaceText(find: string, replace: string, options?: { all?: boolean }): DomRule;
    attr(name: string, value: unknown): DomRule;
    attrs(attributes: Record<string, unknown>): DomRule;
    removeAttr(name: string): DomRule;
    style(styles: Record<string, unknown>): DomRule;
    css(name: string, value: unknown): DomRule;
    addClass(value: string): DomRule;
    removeClass(value: string): DomRule;
    hide(): DomRule;
    show(): DomRule;
    remove(): DomRule;
    replaceWith(html: string): DomRule;
    isolate(options?: Record<string, unknown>): DomRule;
    click(): DomRule;
    focus(): DomRule;
    value(value: unknown): DomRule;
    observe(enabled?: boolean): DomRule;
  };

  export type WebBridge = {
    readonly id: string;
    expose(name: string, callback: (arguments: unknown) => unknown | Promise<unknown>): WebBridge;
    unexpose(name: string): WebBridge;
    callPage(method: string, arguments?: unknown): Promise<unknown>;
    evaluate(source: string): Promise<unknown>;
    apply(...rules: DomRule[]): Promise<unknown>;
    reload(): Promise<void>;
    stop(): Promise<void>;
    goBack(): Promise<void>;
    goForward(): Promise<void>;
    canGoBack(): Promise<boolean>;
    canGoForward(): Promise<boolean>;
    getUrl(): Promise<string | null>;
    getTitle(): Promise<string | null>;
    getCookies(url?: string): Promise<WebCookie[]>;
    setCookies(cookies: WebCookie[]): Promise<void>;
    clearCookies(): Promise<boolean>;
    clearCache(): Promise<void>;
    clearLocalStorage(): Promise<void>;
    loadUrl(url: string, options?: { headers?: Record<string, string> }): Promise<void>;
    loadHtml(html: string, options?: { baseUrl?: string }): Promise<void>;
  };

  export type WebViewProps = {
    key?: string;
    url?: string;
    html?: string;
    baseUrl?: string;
    headers?: Record<string, string>;
    bridge?: WebBridge;
    bridgeId?: string;
    rules?: DomRule | DomRule[];
    frameScripts?: string[];
    initialCookies?: WebCookie[];
    javaScriptEnabled?: boolean;
    zoomEnabled?: boolean;
    userAgent?: string;
    onPageStarted?: JsUiEvent;
    onPageFinished?: JsUiEvent;
    onProgress?: JsUiEvent;
    onUrlChanged?: JsUiEvent;
    onMessage?: JsUiEvent;
    onError?: JsUiEvent;
  };

  export function dom(selector: string): DomRule;
  export function webRules(...rules: Array<DomRule | DomRule[]>): unknown[];
  export function createWebBridge(id?: string): WebBridge;
  export function WebView(props: WebViewProps): JsUiNode;
}
