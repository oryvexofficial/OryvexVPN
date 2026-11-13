# راهنمای سئو VexoStream (نسخه 21)

## چیزهایی که توی کد درست شد
1. **گوگل‌بات دیگه بلاک نمی‌شه.** مهم‌ترین مشکل همین بود: سیستم ضد اسکرپ، گوگل‌بات رو مثل اسکرپر محدود و بن می‌کرد و API کارت‌ها رو هم بهش نمی‌داد، یعنی گوگل صفحه‌ها رو خالی می‌دید. الان ربات‌های واقعی گوگل، بینگ، داک‌داک‌گو، یاندکس و اپل (با چک ASN / verified bot کلودفلر) رد می‌شن. گوگل‌بات تقلبی هنوز بلاکه. استریم‌ها همچنان قفلن.
2. **sitemap.xml** و **robots.txt** درست (آدرس sitemap داخلشه).
3. **canonical** روی همه صفحه‌ها + ریدایرکت 301 از www به دامنه اصلی.
4. **title و description** درست با اسم VexoStream روی همه صفحه‌ها. صفحه‌های جستجو، لاگین و ویدیوها noindex شدن (محتوای تکراری/پشت لاگین گوگل رو اذیت می‌کنه).
5. **Schema (JSON-LD):** Organization + WebSite روی صفحه اصلی، breadcrumb روی browse.
6. **برچسب بزرگسالان** (rating=adult + RTA): گوگل برای سایت‌های 18+ اجباری می‌دونه. نذاری ممکنه کل سایت جریمه بشه.
7. **Lighthouse:** فونت‌ها دیگه رندر رو بلاک نمی‌کنن، فونت فارسی فقط وقتی صفحه RTL باشه لود می‌شه، back/forward cache فعال شد، صفحه status سریع‌تر شد، favicon PNG و manifest اضافه شد.

## کارهایی که خودت باید بکنی (به ترتیب)
1. **دیپلوی:** `npm install` و بعد `npm run deploy`.
2. **Google Search Console:** https://search.google.com/search-console → Add property → نوع **Domain** → `vexostream.bond` → رکورد TXT رو توی DNS کلودفلر بزن.
3. همون‌جا **Sitemaps** → `https://vexostream.bond/sitemap.xml` رو Submit کن.
4. **URL Inspection** → `https://vexostream.bond/` → **Request indexing**. همین کار رو برای چند تا `/browse/...` هم بکن.
5. **Bing Webmaster Tools:** https://www.bing.com/webmasters → Import from Google Search Console (بینگ = داک‌داک‌گو و یاهو هم).
6. **کلودفلر:**
   - SSL/TLS → **Always Use HTTPS** روشن.
   - Security → Bots: اگه Bot Fight Mode روشنه، مطمئن شو **Verified bots = Allow**. «Block AI bots» اشکالی نداره ولی گوگل‌بات رو نبند.
   - Caching → **Crawler Hints** روشن.
7. **سیگنال برند (خیلی مهم برای اینکه با سرچ "VexoStream" بیای اول):**
   - توی بیو کانال تلگرام، X، ردیت، اینستا و... لینک `https://vexostream.bond` رو بذار.
   - همون اکانت‌ها رو توی **Admin > Social media** وارد کن، خودکار به schema (sameAs) اضافه می‌شن و گوگل می‌فهمه همه مال یه برندن.
   - همه‌جا اسم رو دقیقاً **VexoStream** بنویس (نه Vexo Stream یا vexo-stream).
8. **PageSpeed Insights:** بعد از دیپلوی https://pagespeed.web.dev رو روی صفحه اصلی بزن و عدد موبایل رو ببین.

## واقعیت ماجرا (بی‌تعارف)
- **سرچ "VexoStream":** اسمت یکتاست و دامنه هم همین اسمه، پس بعد از ایندکس شدن (معمولاً چند روز تا 2-4 هفته) باید اول بیای. این شدنیه.
- **سرچ کلمات عمومی** مثل "porn" یا "free hd videos": اول شدن در برابر Pornhub و xvideos عملاً غیرممکنه، وقت و پول روش نذار.
- **SafeSearch:** سایت بزرگسالانه، برای کسایی که SafeSearch گوگل روشنه (مثلاً خیلی از اکانت‌های زیر 18 و بعضی کشورها) اصلاً نشون داده نمی‌شه. این قابل دور زدن نیست.
- **ویدیوها پشت لاگین هستن** پس توی گوگل ایندکس نمی‌شن. فقط صفحه اصلی، browse و بقیه صفحه‌های عمومی میان.
- **شمارنده "N watching" شبیه‌سازی‌شده** (1M تا 9M): عدد فیک اعتماد کاربر رو خراب می‌کنه. پیشنهادم اینه از Admin > Live viewers روی **Real visitors** بذاری.
- **هیچ‌وقت** بک‌لینک نخر، متن مخفی نذار و کلمه کلیدی تکراری نریز. گوگل برای این‌ها کل دامنه رو جریمه می‌کنه.
