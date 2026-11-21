-- Полная миграция: все новые функции
-- Выполнить в Supabase SQL Editor для существующих баз данных

-- 1. Добавление настроек приватности
alter table public.profiles 
add column if not exists privacy_messages text default 'everyone' 
check (privacy_messages in ('everyone', 'request'));

-- 2. Добавление изображений в сообщения
alter table public.messages 
add column if not exists image_url text;

-- 3. Политика удаления сообщений
drop policy if exists "messages own delete" on public.messages;
create policy "messages own delete" on public.messages for delete using (auth.uid() = sender_id);

-- 4. Политика удаления комментариев
drop policy if exists "comments own write" on public.comments;
drop policy if exists "comments own delete" on public.comments;
create policy "comments own write" on public.comments for insert with check (auth.uid() = author_id);
create policy "comments own delete" on public.comments for delete using (auth.uid() = author_id);

-- 5. Политика удаления чатов
drop policy if exists "conversations delete" on public.conversations;
create policy "conversations delete" on public.conversations for delete using (public.is_conversation_member(id));

comment on column public.profiles.privacy_messages is 'Настройки приватности сообщений: everyone = все могут писать, request = только по запросу';
comment on column public.messages.image_url is 'URL изображения в сообщении';


-- 6. Добавление ответов на комментарии
alter table public.comments 
add column if not exists parent_id uuid references public.comments(id) on delete cascade;

create index if not exists idx_comments_parent_id on public.comments(parent_id);

comment on column public.comments.parent_id is 'ID родительского комментария для ответов';
