-- Luma: выполнить целиком в Supabase SQL Editor
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (username ~ '^[a-zA-Z0-9_.-]{3,30}$'),
  full_name text not null check (char_length(full_name) between 2 and 80),
  avatar_url text,
  cover_url text,
  bio text default '',
  city text default '',
  privacy_messages text default 'everyone' check (privacy_messages in ('everyone', 'request')),
  created_at timestamptz not null default now()
);
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  image_url text,
  created_at timestamptz not null default now()
);
create table if not exists public.post_likes (
  post_id uuid references public.posts(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  primary key (post_id, user_id)
);
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade,
  author_id uuid references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create table if not exists public.follows (
  follower_id uuid references public.profiles(id) on delete cascade,
  following_id uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid references public.conversations(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  primary key (conversation_id, user_id)
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.conversations(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.comments enable row level security;
alter table public.follows enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;

drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select using (true);
drop policy if exists "profile own insert" on public.profiles;
create policy "profile own insert" on public.profiles for insert with check (auth.uid() = id);
drop policy if exists "profile own update" on public.profiles;
create policy "profile own update" on public.profiles for update using (auth.uid() = id);

drop policy if exists "posts readable" on public.posts;
create policy "posts readable" on public.posts for select using (true);
drop policy if exists "posts own write" on public.posts;
create policy "posts own write" on public.posts for all using (auth.uid() = author_id) with check (auth.uid() = author_id);

drop policy if exists "likes readable" on public.post_likes;
create policy "likes readable" on public.post_likes for select using (true);
drop policy if exists "likes own write" on public.post_likes;
create policy "likes own write" on public.post_likes for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "comments readable" on public.comments;
create policy "comments readable" on public.comments for select using (true);
drop policy if exists "comments own write" on public.comments;
create policy "comments own write" on public.comments for all using (auth.uid() = author_id) with check (auth.uid() = author_id);

drop policy if exists "follows readable" on public.follows;
create policy "follows readable" on public.follows for select using (true);
drop policy if exists "follows own write" on public.follows;
create policy "follows own write" on public.follows for all using (auth.uid() = follower_id) with check (auth.uid() = follower_id);

create or replace function public.is_conversation_member(target uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from conversation_members where conversation_id = target and user_id = auth.uid()) $$;

drop policy if exists "members own read" on public.conversation_members;
create policy "members own read" on public.conversation_members for select using (user_id = auth.uid() or public.is_conversation_member(conversation_id));
drop policy if exists "members own write" on public.conversation_members;
create policy "members own write" on public.conversation_members for insert with check (user_id = auth.uid());
drop policy if exists "conversations members" on public.conversations;
create policy "conversations members" on public.conversations for select using (public.is_conversation_member(id));
drop policy if exists "conversations create" on public.conversations;
create policy "conversations create" on public.conversations for insert with check (auth.uid() is not null);
drop policy if exists "messages members" on public.messages;
create policy "messages members" on public.messages for select using (public.is_conversation_member(conversation_id));
drop policy if exists "messages own insert" on public.messages;
create policy "messages own insert" on public.messages for insert with check (auth.uid() = sender_id and public.is_conversation_member(conversation_id));

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$ begin insert into public.profiles (id, username, full_name) values (new.id, coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text,1,8)), coalesce(new.raw_user_meta_data->>'full_name','Новый пользователь')); return new; end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.messages replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
end $$;

create or replace function public.start_conversation(other uuid)
returns uuid language plpgsql security definer set search_path = public
as $$
declare cid uuid;
begin
  if other = auth.uid() then raise exception 'Нельзя написать самому себе'; end if;
  select m1.conversation_id into cid
  from conversation_members m1
  join conversation_members m2 on m2.conversation_id = m1.conversation_id
  where m1.user_id = auth.uid() and m2.user_id = other
    and (select count(*) from conversation_members m3 where m3.conversation_id = m1.conversation_id) = 2
  limit 1;
  if cid is null then
    insert into conversations default values returning id into cid;
    insert into conversation_members (conversation_id, user_id) values (cid, auth.uid()), (cid, other);
  end if;
  return cid;
end;
$$;
grant execute on function public.start_conversation(uuid) to authenticated;

insert into storage.buckets (id, name, public) values
  ('avatars', 'avatars', true), ('covers', 'covers', true), ('posts', 'posts', true)
on conflict (id) do update set public = true;

drop policy if exists "images public read" on storage.objects;
create policy "images public read" on storage.objects for select
  using (bucket_id in ('avatars', 'covers', 'posts'));
drop policy if exists "images user insert" on storage.objects;
create policy "images user insert" on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars', 'covers', 'posts') and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "images user update" on storage.objects;
create policy "images user update" on storage.objects for update to authenticated
  using (owner = auth.uid());
drop policy if exists "images user delete" on storage.objects;
create policy "images user delete" on storage.objects for delete to authenticated
  using (owner = auth.uid());
