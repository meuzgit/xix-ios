-- 0005: callouts and per-target responses (Build Doc 1 v1.2 A.2, Build Doc 2 A.2 #5)

create table xix.callouts (
  id          uuid primary key default gen_random_uuid(),
  round_id    uuid not null references xix.rounds (id) on delete cascade,
  hole        smallint not null check (hole between 1 and 18),
  kind        text not null check (kind in ('target', 'duel', 'partner', 'multiplier')),
  caller_id   uuid not null,
  target_ids  uuid[] not null check (cardinality(target_ids) >= 1),  -- one player, or all others; never the caller
  params      jsonb not null default '{}'::jsonb,
  -- Derived from responses and scores: open (no signature, hole open), live (a signature, awaiting scores),
  -- expired (hole closed with no signature), resolved (written by the engine runtime).
  status      text not null default 'open' check (status in ('open', 'live', 'expired', 'resolved')),
  closed_at   timestamptz,                             -- set when a participant scores the hole; no more responses
  created_at  timestamptz not null default now(),
  unique (id, round_id),
  foreign key (caller_id, round_id) references xix.players (id, round_id) on delete cascade
);

create table xix.callout_responses (
  callout_id    uuid not null references xix.callouts (id) on delete cascade,
  player_id     uuid not null references xix.players (id) on delete cascade,   -- must be in callouts.target_ids (trigger + RPC)
  action        text not null check (action in ('signed', 'ducked')),
  responded_at  timestamptz not null default now(),
  primary key (callout_id, player_id)
);

grant select on xix.callouts to authenticated;
grant select on xix.callout_responses to authenticated;
