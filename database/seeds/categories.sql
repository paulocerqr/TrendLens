BEGIN;

INSERT INTO categories (slug, name, description)
VALUES
    ('movie_tv_clips', 'Cortes de filmes e séries', 'Cenas ou trechos de filmes e séries, com atenção especial a risco de conteúdo reutilizado.'),
    ('podcast_clips', 'Cortes de podcasts', 'Trechos curtos derivados de entrevistas, conversas e podcasts.'),
    ('curiosities', 'Curiosidades', 'Conteúdo informativo curto baseado em fatos, descobertas e perguntas.'),
    ('technology', 'Tecnologia', 'Notícias, explicações, comparações e dicas relacionadas a tecnologia.'),
    ('games', 'Games', 'Gameplay, notícias, curiosidades e comentários sobre jogos.'),
    ('humor', 'Humor', 'Esquetes, situações cômicas, memes e comentários humorísticos.'),
    ('quick_tutorials', 'Tutoriais rápidos', 'Instruções práticas e demonstrações curtas.'),
    ('sports', 'Esportes', 'Notícias, análises, curiosidades e comentários esportivos.'),
    ('storytelling', 'Storytelling', 'Narrativas curtas baseadas em histórias, experiências ou eventos.'),
    ('motivation', 'Conteúdo motivacional', 'Mensagens, histórias e orientações de caráter motivacional.')
ON CONFLICT (slug) DO UPDATE
SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    active = TRUE;

COMMIT;
