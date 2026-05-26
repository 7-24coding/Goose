<div align="center">
  <img src="goose_vpn_app/assests/logo/logo.png" alt="Goose VPN Logo" width="150" />
  
  # GooseRelay VPN Client (Android)
  
  **A beautiful, optimized, and smart Android client for GooseRelayVPN.**
  
  [![Platform](https://img.shields.io/badge/Platform-Android-green.svg)](https://android.com)
  [![Framework](https://img.shields.io/badge/Framework-Flutter-blue.svg)](https://flutter.dev)
  [![Language](https://img.shields.io/badge/Language-Go%20%7C%20Dart-00ADD8.svg)](https://golang.org)
</div>

<br/>

*For the Persian (Farsi) documentation, please scroll down.*
*برای مطالعه توضیحات فارسی، لطفاً به پایین صفحه مراجعه کنید.*

---

## 🌍 English Documentation

### Overview
This project is an advanced, open-source Android client designed specifically for **[GooseRelayVPN](https://github.com/Kianmhz/GooseRelayVPN)**. 
The primary goal of this project is to provide a seamless, user-friendly Android interface with major under-the-hood optimizations to bypass censorship efficiently while strictly managing server-side quota consumption.

### ✨ Key Features

*   **Two Operation Modes:**
    *   **🛡️ VPN Mode (Full Device Tunnel):** Tunnels all network traffic on your Android device. Due to the unique nature of the GooseRelay protocol, this method successfully bypasses IP-sensitive restrictions, granting you unrestricted access to services like **Cloudflare, ChatGPT, Gemini, and Google Services**.
    *   **🔌 Proxy Mode:** Creates a local SOCKS5 proxy (e.g., `127.0.0.1:1080`) that you can manually plug into specific apps like Telegram or web browsers without routing the entire device traffic.
*   **🔋 Extreme Quota Optimization:**
    *   **Frame Coalescing/Batching:** Multiple requests are compressed and batched together to drastically reduce the number of HTTP requests sent to the relay server.
    *   **Smart Idle Cut-off:** To save your precious Apps Script quota, the Go backend intelligently detects network inactivity. If no data is transmitted or received for ~1-2 minutes, the background polling is **completely halted**. The moment a new request is made, the tunnel wakes up instantly.
*   **🧠 Smart Routing:** Intelligently bypasses the VPN tunnel for domestic/local domains (e.g., `.ir` domains, local banks, Snapp, etc.), ensuring maximum speed for local services without consuming your VPN bandwidth.
*   **🎨 Premium UI:** Built entirely with **Flutter**, featuring a modern, dark-themed, and animated user interface that provides a premium user experience.

### 🏗️ Architecture
- **Frontend:** Flutter (Dart)
- **Core Network Engine:** Go (Golang) bridging to Android via `gomobile`.
- **Tunneling Protocol:** Integrates `tun2socks` to capture OS-level traffic and route it through a custom SOCKS5 handler that communicates with the GooseRelay Google Apps Script backend.

### 🙏 Acknowledgments
This client is heavily based on and acts as a specialized Android fork of the original **[Kianmhz/GooseRelayVPN](https://github.com/Kianmhz/GooseRelayVPN)** project. 

---
<br/>

## 🇮🇷 توضیحات فارسی (Persian)

### معرفی پروژه
این پروژه یک کلاینت اختصاصی، متن‌باز و بهینه‌شده‌ی اندروید برای پروژه‌ی **[GooseRelayVPN](https://github.com/Kianmhz/GooseRelayVPN)** است.
هدف اصلی از ایجاد این پروژه، ساخت یک رابط کاربری ساده، زیبا و قدرتمند برای سیستم‌عامل اندروید بوده است تا کاربران بتوانند به راحتی از پروتکل GooseRelay استفاده کنند و در عین حال مصرف ترافیک و کوتای سرور به بهینه‌ترین شکل ممکن مدیریت شود.

### ✨ ویژگی‌های کلیدی

*   **دو حالت اتصال مجزا:**
    *   **🛡️ حالت VPN (تونل کل گوشی):** تمام ترافیک اینترنت گوشی شما را تونل می‌کند. به لطف ساختار خاص این متد، دسترسی به تمام سایت‌ها و برنامه‌هایی که به IP حساس هستند (مثل **سرویس‌های گوگل، کلادفلر و هوش‌مصنوعی‌هایی مثل ChatGPT و Gemini**) بدون هیچ مشکلی فراهم می‌شود.
    *   **🔌 حالت پروکسی:** یک پروکسی محلی (مثلاً `127.0.0.1:1080`) روی گوشی شما می‌سازد که می‌توانید فقط برنامه‌های خاصی (مثل تلگرام یا مرورگرها) را به آن متصل کنید.
*   **🔋 بهینه‌سازی شدید مصرف کوتا (Quota):**
    *   **فشرده‌سازی و تجمیع درخواست‌ها (Batching):** ریکوئست‌ها برای کاهش فشار روی سرور و مصرف کوتا، فشرده و در قالب بسته‌های تجمیع‌شده ارسال می‌شوند.
    *   **قطع هوشمند مصرف در زمان بیکاری:** برای جلوگیری از هدر رفتن کوتای Google Apps Script، هسته‌ی برنامه به صورت هوشمند طوری طراحی شده که اگر حدود یک الی دو دقیقه هیچ دیتایی رد و بدل نشود، ارسال درخواست‌های پس‌زمینه **کاملاً قطع می‌شود**. به محض باز کردن یک برنامه یا ارسال یک درخواست جدید، ارتباط در کسری از ثانیه مجدداً متصل می‌شود.
*   **🧠 مسیریابی هوشمند (Smart Routing):** سایت‌ها و اپلیکیشن‌های داخلی (مثل دامنه‌های `.ir`، اپلیکیشن‌های بانکی، اسنپ و...) به صورت خودکار تشخیص داده شده و از تونل VPN عبور نمی‌کنند (مستقیماً با اینترنت بدون فیلتر باز می‌شوند). این کار سرعت شما را افزایش داده و از مصرف بی‌دلیل ترافیک VPN جلوگیری می‌کند.
*   **🎨 رابط کاربری مدرن:** کلاینت با استفاده از **فریم‌ورک فلاتر (Flutter)** ساخته شده و دارای یک رابط کاربری تاریک (Dark Mode)، جذاب و انیمیشن‌دار است که حس یک اپلیکیشن کاملاً حرفه‌ای را به کاربر منتقل می‌کند.

### 🏗️ معماری نرم‌افزار
- **رابط کاربری (فرانت‌اند):** Flutter (Dart)
- **هسته شبکه (بک‌اند):** نوشته شده با زبان گو (Go) که از طریق ابزار `gomobile` با کدهای اندروید ارتباط برقرار می‌کند.
- **تکنولوژی تونلینگ:** استفاده از `tun2socks` برای تبدیل ترافیک کل سیستم‌عامل به پروکسی SOCKS5 و ارسال آن به سمت بک‌اند Google Apps Script.

### 🙏 تقدیر و تشکر
این نرم‌افزار یک فورک تخصصی برای اندروید از پروژه‌ی اصلی **[Kianmhz/GooseRelayVPN](https://github.com/Kianmhz/GooseRelayVPN)** است و بر پایه‌ی ایده‌ها و معماری این پروژه توسعه یافته است.

---
> 🌟 **If you find this project useful, please consider giving it a Star!**
> 🌟 **اگر این پروژه برای شما مفید بود، لطفاً با دادن ستاره (Star) از ما حمایت کنید!**
