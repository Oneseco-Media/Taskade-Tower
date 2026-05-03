
const axios = require('axios');

const NOTION_API_BASE = 'https://api.notion.com/v1';
const NOTION_VERSION = '2022-06-28';

class NotionService {
  constructor() {
    this.clientId = process.env.NOTION_OAUTH_CLIENT_ID;
    this.clientSecret = process.env.NOTION_OAUTH_CLIENT_SECRET;
    this.redirectUri = process.env.NOTION_REDIRECT_URI || 'https://oneseco.com';

    if (!this.clientId || !this.clientSecret) {
      throw new Error('NOTION_OAUTH_CLIENT_ID and NOTION_OAUTH_CLIENT_SECRET environment variables are required');
    }

    // In-memory token store keyed by workspace_id
    this.tokens = {};
  }

  getAuthorizationUrl(state = '') {
    const params = new URLSearchParams({
      client_id: this.clientId,
      response_type: 'code',
      owner: 'user',
      redirect_uri: this.redirectUri,
    });
    if (state) params.set('state', state);
    return `${NOTION_API_BASE}/oauth/authorize?${params.toString()}`;
  }

  async exchangeCodeForToken(code) {
    const credentials = Buffer.from(`${this.clientId}:${this.clientSecret}`).toString('base64');
    const response = await axios.post(
      `${NOTION_API_BASE}/oauth/token`,
      {
        grant_type: 'authorization_code',
        code,
        redirect_uri: this.redirectUri,
      },
      {
        headers: {
          Authorization: `Basic ${credentials}`,
          'Content-Type': 'application/json',
        },
      }
    );
    const tokenData = response.data;
    if (tokenData.workspace_id) {
      this.tokens[tokenData.workspace_id] = tokenData;
    }
    return tokenData;
  }

  _headers(accessToken) {
    return {
      Authorization: `Bearer ${accessToken}`,
      'Notion-Version': NOTION_VERSION,
      'Content-Type': 'application/json',
    };
  }

  async search(accessToken, query = '', filter = null) {
    const body = { query };
    if (filter) body.filter = filter;
    const response = await axios.post(`${NOTION_API_BASE}/search`, body, {
      headers: this._headers(accessToken),
    });
    return response.data;
  }

  async getPage(accessToken, pageId) {
    const response = await axios.get(`${NOTION_API_BASE}/pages/${pageId}`, {
      headers: this._headers(accessToken),
    });
    return response.data;
  }

  async getPageBlocks(accessToken, blockId) {
    const response = await axios.get(`${NOTION_API_BASE}/blocks/${blockId}/children`, {
      headers: this._headers(accessToken),
    });
    return response.data;
  }

  async createPage(accessToken, parentId, parentType, title, properties = {}, children = []) {
    const parent = parentType === 'database'
      ? { database_id: parentId }
      : { page_id: parentId };

    const body = {
      parent,
      properties: {
        title: {
          title: [{ text: { content: title } }],
        },
        ...properties,
      },
    };
    if (children.length > 0) body.children = children;

    const response = await axios.post(`${NOTION_API_BASE}/pages`, body, {
      headers: this._headers(accessToken),
    });
    return response.data;
  }

  async updatePage(accessToken, pageId, properties) {
    const response = await axios.patch(`${NOTION_API_BASE}/pages/${pageId}`, { properties }, {
      headers: this._headers(accessToken),
    });
    return response.data;
  }

  async archivePage(accessToken, pageId) {
    const response = await axios.patch(
      `${NOTION_API_BASE}/pages/${pageId}`,
      { archived: true },
      { headers: this._headers(accessToken) }
    );
    return response.data;
  }

  async getDatabase(accessToken, databaseId) {
    const response = await axios.get(`${NOTION_API_BASE}/databases/${databaseId}`, {
      headers: this._headers(accessToken),
    });
    return response.data;
  }

  async queryDatabase(accessToken, databaseId, filter = null, sorts = [], startCursor = null, pageSize = 100) {
    const body = { page_size: pageSize };
    if (filter) body.filter = filter;
    if (sorts.length > 0) body.sorts = sorts;
    if (startCursor) body.start_cursor = startCursor;

    const response = await axios.post(`${NOTION_API_BASE}/databases/${databaseId}/query`, body, {
      headers: this._headers(accessToken),
    });
    return response.data;
  }

  async appendBlockChildren(accessToken, blockId, children) {
    const response = await axios.patch(
      `${NOTION_API_BASE}/blocks/${blockId}/children`,
      { children },
      { headers: this._headers(accessToken) }
    );
    return response.data;
  }

  async getUsers(accessToken) {
    const response = await axios.get(`${NOTION_API_BASE}/users`, {
      headers: this._headers(accessToken),
    });
    return response.data;
  }
}

module.exports = NotionService;
