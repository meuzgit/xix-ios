-- Local only: dummy Vault secrets so the engine webhook trigger (0018) has something to read.
-- The local function is reachable from the database container through the Docker host alias.
select vault.create_secret('local-dummy-service-role-key', 'xix_service_role_key', 'local stand-in; never a real key');
select vault.create_secret('http://host.docker.internal:54321/functions/v1/xix-engine', 'xix_engine_url', 'local edge runtime');
