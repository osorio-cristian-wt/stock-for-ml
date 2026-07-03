-- Auto-register ML cron jobs on migration apply.
-- Safe-guard: only execute when required app_config values are present.
do $$
begin
	if exists (
		select 1
		from private.app_config
		where key = 'functions_base_url'
			and nullif(value, '') is not null
	)
	and exists (
		select 1
		from private.app_config
		where key = 'service_role_key'
			and nullif(value, '') is not null
	) then
		perform private.register_ml_cron_jobs();
	else
		raise notice 'Skipping private.register_ml_cron_jobs(): missing private.app_config keys';
	end if;
end
$$;
