export type GitHubReleaseAsset = {
  name: string;
  browser_download_url: string;
  content_type?: string;
  state?: string;
};

type GitHubLatestRelease = {
  tag_name?: string;
  html_url?: string;
  assets?: GitHubReleaseAsset[];
};

type FetchLatestDmgAssetOptions = {
  owner: string;
  repo: string;
  token?: string;
  fetchFn?: typeof fetch;
};

export type LatestDmgAsset = {
  tagName: string | null;
  asset: GitHubReleaseAsset;
};

export class DownloadReleaseError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(statusCode: number, code: string, message: string) {
    super(message);
    this.name = 'DownloadReleaseError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

export function findDmgAsset(assets: GitHubReleaseAsset[]): GitHubReleaseAsset | null {
  const dmgAssets = assets.filter((asset) => {
    const isUploaded = !asset.state || asset.state === 'uploaded';
    return isUploaded && /\.dmg$/i.test(asset.name) && Boolean(asset.browser_download_url);
  });

  if (dmgAssets.length === 0) {
    return null;
  }

  return (
    dmgAssets.find((asset) => /^sayless(?:[-_\s].*)?\.dmg$/i.test(asset.name)) ??
    dmgAssets.find((asset) => /sayless/i.test(asset.name)) ??
    dmgAssets[0]
  );
}

export async function fetchLatestDmgAsset({
  owner,
  repo,
  token,
  fetchFn = fetch
}: FetchLatestDmgAssetOptions): Promise<LatestDmgAsset> {
  const apiUrl = `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/releases/latest`;
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'Sayless-Download-Redirector',
    'X-GitHub-Api-Version': '2022-11-28'
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetchFn(apiUrl, {
    headers
  });

  if (!response.ok) {
    throw new DownloadReleaseError(
      response.status >= 500 ? 502 : response.status,
      'github_release_lookup_failed',
      `GitHub latest release lookup failed with status ${response.status}`
    );
  }

  const release = (await response.json()) as GitHubLatestRelease;
  const asset = findDmgAsset(release.assets ?? []);

  if (!asset) {
    throw new DownloadReleaseError(404, 'dmg_asset_not_found', 'Latest GitHub release does not include a .dmg asset');
  }

  return {
    tagName: release.tag_name ?? null,
    asset
  };
}
