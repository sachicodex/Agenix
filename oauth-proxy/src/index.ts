interface Env {
	GOOGLE_CLIENT_ID: string;
	GOOGLE_CLIENT_SECRET: string;
}

const jsonHeaders = {
	'content-type': 'application/json',
	'access-control-allow-origin': '*',
	'access-control-allow-methods': 'POST, OPTIONS',
	'access-control-allow-headers': 'content-type',
};

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: jsonHeaders,
	});
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		if (request.method === 'OPTIONS') {
			return new Response(null, { status: 204, headers: jsonHeaders });
		}

		const url = new URL(request.url);
		if (url.pathname !== '/oauth/token') {
			return jsonResponse({ error: 'not_found' }, 404);
		}

		if (request.method !== 'POST') {
			return jsonResponse({ error: 'method_not_allowed' }, 405);
		}

		let payload: Record<string, unknown>;
		try {
			payload = (await request.json()) as Record<string, unknown>;
		} catch {
			return jsonResponse({ error: 'invalid_json' }, 400);
		}

		const grantType = String(payload.grant_type ?? '');
		if (grantType != 'authorization_code' && grantType != 'refresh_token') {
			return jsonResponse({ error: 'unsupported_grant_type' }, 400);
		}

		const body = new URLSearchParams();
		body.set('grant_type', grantType);
		body.set('client_id', env.GOOGLE_CLIENT_ID);
		body.set('client_secret', env.GOOGLE_CLIENT_SECRET);

		if (grantType === 'authorization_code') {
			const code = String(payload.code ?? '');
			const redirectUri = String(payload.redirect_uri ?? '');
			const codeVerifier = String(payload.code_verifier ?? '');
			if (!code || !redirectUri || !codeVerifier) {
				return jsonResponse(
					{ error: 'missing_fields', required: ['code', 'redirect_uri', 'code_verifier'] },
					400,
				);
			}
			body.set('code', code);
			body.set('redirect_uri', redirectUri);
			body.set('code_verifier', codeVerifier);
		} else {
			const refreshToken = String(payload.refresh_token ?? '');
			if (!refreshToken) {
				return jsonResponse({ error: 'missing_fields', required: ['refresh_token'] }, 400);
			}
			body.set('refresh_token', refreshToken);
		}

		const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
			method: 'POST',
			headers: { 'content-type': 'application/x-www-form-urlencoded' },
			body,
		});

		return new Response(await tokenResp.text(), {
			status: tokenResp.status,
			headers: jsonHeaders,
		});
	},
} satisfies ExportedHandler<Env>;
