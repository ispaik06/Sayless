import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { DownloadReleaseError, fetchLatestDmgAsset, findDmgAsset } from './downloadRelease.js';

describe('findDmgAsset', () => {
  it('selects a Sayless dmg over other dmg assets', () => {
    const asset = findDmgAsset([
      {
        name: 'notes.dmg',
        browser_download_url: 'https://example.com/notes.dmg'
      },
      {
        name: 'Sayless-0.2.0.dmg',
        browser_download_url: 'https://example.com/Sayless-0.2.0.dmg'
      }
    ]);

    assert.equal(asset?.name, 'Sayless-0.2.0.dmg');
  });

  it('ignores non-dmg and non-uploaded assets', () => {
    const asset = findDmgAsset([
      {
        name: 'Sayless.zip',
        browser_download_url: 'https://example.com/Sayless.zip'
      },
      {
        name: 'Sayless.dmg',
        state: 'starter',
        browser_download_url: 'https://example.com/Sayless.dmg'
      }
    ]);

    assert.equal(asset, null);
  });
});

describe('fetchLatestDmgAsset', () => {
  it('returns the latest release dmg asset from GitHub API payload', async () => {
    const result = await fetchLatestDmgAsset({
      owner: 'ispaik06',
      repo: 'Sayless',
      fetchFn: async () =>
        new Response(
          JSON.stringify({
            tag_name: 'v1.2.3',
            assets: [
              {
                name: 'Sayless-1.2.3.dmg',
                browser_download_url: 'https://github.com/ispaik06/Sayless/releases/download/v1.2.3/Sayless-1.2.3.dmg'
              }
            ]
          }),
          {
            status: 200,
            headers: {
              'content-type': 'application/json'
            }
          }
        )
    });

    assert.equal(result.tagName, 'v1.2.3');
    assert.equal(result.asset.name, 'Sayless-1.2.3.dmg');
  });

  it('throws a 404 when the latest release has no dmg asset', async () => {
    await assert.rejects(
      fetchLatestDmgAsset({
        owner: 'ispaik06',
        repo: 'Sayless',
        fetchFn: async () =>
          new Response(
            JSON.stringify({
              tag_name: 'v1.2.3',
              assets: []
            }),
            {
              status: 200,
              headers: {
                'content-type': 'application/json'
              }
            }
          )
      }),
      (error) => error instanceof DownloadReleaseError && error.statusCode === 404 && error.code === 'dmg_asset_not_found'
    );
  });
});
