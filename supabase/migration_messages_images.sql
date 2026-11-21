-- Миграция: добавление изображений в сообщения
-- Выполнить в Supabase SQL Editor

alter table public.messages 
add column if not exists image_url text;

comment on column public.messages.image_url is 'URL изображения в сообщении';
