# Social & bot icons

Official single-colour brand marks, downloaded from the Simple Icons project
(https://simpleicons.org, CC0-1.0):

telegram, x, instagram, youtube, tiktok, discord, reddit, whatsapp, facebook,
messenger, line, viber, slack (slack.svg comes from Simple Icons 10.0.0; it
was removed from later releases at Slack's request).

`website.svg` (globe) and `bot.svg` are from Lucide (https://lucide.dev, ISC).

All brand names and logos belong to their owners. Follow each brand's
guidelines when you change colours or shapes.

How they are used: `npm run build` embeds every SVG here into the Worker.
They are drawn inline (currentColor) on the Social page, burger menu, footer
and admin, and are also served as files at `/assets/icons/<name>.svg`.
To swap an icon, replace the file with the same name and rebuild.
