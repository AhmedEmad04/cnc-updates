#Encoding: UTF-8
# ==============================================================================
# ملف: main_loader.rb
# (النسخة النهائية والأكثر أماناً: التحقق القسري من الترخيص عند فتح المكتبة)
# ==============================================================================

require 'sketchup.rb'
require 'extensions.rb'
require 'json'
require 'base64'
require 'pathname'
require 'fileutils'
require 'openssl'
require 'net/http'
require 'uri'
require 'digest'
require 'win32ole'
require 'win32/registry'

module ClickAndCut

  # 1. تعريف رقم الإصدار الحالي
  CURRENT_VERSION = "2.0.3" 
  
  # الرابط الصحيح (لم يتغير)
  UPDATE_API_URL = "https://raw.githubusercontent.com/AhmedEmad04/cnc-updates/main/version.json"

  # 2. بصمة ملف الواجهة (لم تتغير)
  UI_HASH = "0b161acf3e2aee885f86bd4799d773b156b2767dcbc83634848136382214c282"

  # ==========================================================================
  # 🔄 وحدة التحديث (Updater Module)
  # ==========================================================================
  module Updater
    API_URL = ClickAndCut::UPDATE_API_URL 
    @@restart_required = false
    @@server_data = nil

    def self.is_restart_required?
      @@restart_required
    end

    # 1. دالة الفحص (لم تتغير)
    def self.check_for_update_availability
      begin
        separator = API_URL.include?('?') ? '&' : '?'
        safe_url = "#{API_URL}#{separator}nocache=#{Time.now.to_i}"
        uri = URI(safe_url)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE 
        
        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)
        
        if response.code != "200"
           puts "❌ Server Error: #{response.code}"
           return false 
        end

        data = JSON.parse(response.body)
        @@server_data = data 

        server_ver = data["version"].to_s.strip
        local_ver = ClickAndCut::CURRENT_VERSION.to_s.strip
        
        puts "🔍 Check: Server(#{server_ver}) vs Local(#{local_ver})"
        return (server_ver > local_ver)
      rescue => e
        puts "❌ Update Error: #{e.message}"
        return false
      end
    end

    # 2. الفحص اليدوي (تم تغيير رسالة "محدث بالفعل" فقط)
    def self.manual_check_ui
      Sketchup.set_status_text("جاري التحقق من التحديثات...")
      has_update = self.check_for_update_availability
      Sketchup.set_status_text("") 

      if has_update
        self.show_update_dialog
      else
        ver = ClickAndCut::CURRENT_VERSION
        # 🔥 تم التعديل: استبدال UI.messagebox بنافذة HTML 🔥
        ClickAndCut::LibraryBrowser.show_update_status_dialog(
          is_success: true, 
          title: "حالة التحديث", 
          message: "نسختك محدثة بالفعل!", 
          details: "الإصدار الحالي: #{ver}"
        )
      end
    end

    # 3. نافذة تفاصيل التحديث (باقية كما هي)
    def self.show_update_dialog
      unless @@server_data; self.check_for_update_availability; end
      return unless @@server_data 

      server_ver = @@server_data["version"]
      update_msg = @@server_data["message"] || "تحسينات عامة."
      
      html_content = <<-HTML
        <!DOCTYPE html>
        <html dir="rtl">
        <head>
          <meta charset="UTF-8">
          <style>
            body { font-family: 'Segoe UI', sans-serif; background: #f8f9fa; padding: 20px; text-align: center; }
            .update-card { background: white; border-radius: 12px; padding: 25px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
            h2 { color: #2c3e50; margin-top: 0; }
            .version-badge { background: #e6f7ff; color: #007bff; padding: 4px 10px; border-radius: 20px; font-weight: bold; }
            .desc { background: #f1f3f5; padding: 15px; border-radius: 8px; margin: 20px 0; text-align: right; color: #555; max-height: 100px; overflow-y: auto; }
            .btn { padding: 10px 25px; border-radius: 6px; border: none; cursor: pointer; font-weight: bold; margin: 5px; }
            .btn-primary { background: #27ae60; color: white; }
            .btn-secondary { background: #ecf0f1; color: #7f8c8d; }
          </style>
        </head>
        <body>
          <div class="update-card">
            <div style="font-size: 40px;">🚀</div>
            <h2>تحديث جديد متاح!</h2>
            <div><span class="version-badge">إصدار #{server_ver}</span></div>
            <div class="desc"><strong>التفاصيل:</strong><br>#{update_msg}</div>
            <div>
              <button class="btn btn-secondary" onclick="window.location='skp:close_dialog'">لاحقاً</button>
              <button class="btn btn-primary" onclick="window.location='skp:start_download_test'">تحديث الآن</button>
            </div>
          </div>
        </body>
        </html>
      HTML

      d = UI::HtmlDialog.new({:dialog_title => "تحديث Click & Cut", :width => 400, :height => 450, :style => UI::HtmlDialog::STYLE_DIALOG})
      d.set_html(html_content); d.center
      d.add_action_callback("close_dialog") { d.close }
      
      d.add_action_callback("start_download_test") do 
        d.close
        self.perform_simple_download(@@server_data["files_to_update"])
      end
      d.show
    end

    # 4. 🔥 التحميل المباشر (الكود الأصلي - تم تغيير الرسائل فقط) 🔥
    def self.perform_simple_download(files_list)
      return unless files_list.is_a?(Array)
      
      folder_path = File.dirname(__FILE__)
      success_count = 0
      
      Sketchup.set_status_text("جاري تحميل التحديثات... يرجى الانتظار")
      
      files_list.each do |file_info|
        file_name = file_info["name"].to_s
        url_str = file_info["url"].to_s
        
        begin
          next unless url_str.start_with?('http')
          target_file = File.join(folder_path, "#{file_name}.new")
          
          uri = URI(url_str)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE 
          
          req = Net::HTTP::Get.new(uri.request_uri)
          res = http.request(req)

          if res.code == "200"
            File.open(target_file, "wb") { |f| f.write(res.body) }
            success_count += 1
            puts "✅ Downloaded: #{file_name}"
          else
            puts "❌ Failed: #{file_name} (Code: #{res.code})"
          end
        rescue => e
          puts "❌ Error downloading #{file_name}: #{e.message}"
        end
      end

      Sketchup.set_status_text("")
      
      if success_count > 0
        @@restart_required = true
        # 🔥 تم التعديل: استبدال UI.messagebox بنافذة HTML 🔥
        ClickAndCut::LibraryBrowser.show_update_status_dialog(
          is_success: true, 
          title: "اكتمل التحميل", 
          message: "تم تحميل الملفات بنجاح!", 
          details: "عدد الملفات: #{success_count}\nيرجى إغلاق SketchUp تماماً وإعادة تشغيله لتثبيت التحديث."
        )
      else
        # 🔥 تم التعديل: استبدال UI.messagebox بنافذة HTML 🔥
        ClickAndCut::LibraryBrowser.show_update_status_dialog(
          is_success: false, 
          title: "فشل التحميل", 
          message: "فشل تحميل الملفات.", 
          details: "تأكد من اتصال الإنترنت."
        )
      end
    end

  end
  
  # ==========================================================================
  # 🔒 وحدة الحماية (لم تتغير)
  # ==========================================================================
  module Protection
    API_URL = "http://cnc-api.atwebpages.com/cnc_api/check.php"
    SECRET_KEY = "ClickAndCut_Super_Secret_Key_2025" 
    @@is_licensed = false
    @@license_message = "جاري التحقق..."
    @@serial_number = "غير متوفر" 
    @@hwid = ""

    def self.is_licensed?; @@is_licensed; end
    def self.get_message; @@license_message; end
    def self.get_serial; @@serial_number; end
    def self.get_hwid_val; @@hwid; end

    def self.get_sketchup_reg_name
      v_str = Sketchup.version.split('.')[0]
      v_int = v_str.to_i
      final_name = "SketchUp #{v_int}"
      if v_int == 23; final_name = "SketchUp 2023"; end
      if v_int == 24; final_name = "SketchUp 2024"; end
      final_name
    end
    
    def self.read_registry_key(key_name)
      val = nil
      begin
        folder = self.get_sketchup_reg_name
        key_path = "Software\\SketchUp\\#{folder}\\ClickAndCut_Pro"
        Win32::Registry::HKEY_CURRENT_USER.open(key_path) do |reg|
          val = reg[key_name]
        end
      rescue; val = nil; end
      val
    end

    def self.get_hwid
      id = "UNKNOWN_ID"
      begin
        file_system = WIN32OLE.new('Scripting.FileSystemObject')
        drive = file_system.GetDrive('C:')
        id = drive.SerialNumber.to_s.strip
      rescue; id = "UNKNOWN_ID"; end
      id
    end

    # 🔥 دالة التحقق من السيرفر (هي قلب نظام الحماية المعقد) 🔥
    def self.force_server_check(serial, current_hwid)
      return true if serial.nil? || serial == "غير مسجل"
      begin
        uri = URI("#{API_URL}?serial=#{serial}&hwid=#{current_hwid}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 3; http.read_timeout = 3
        request = Net::HTTP::Get.new(uri)
        response = http.request(request)
        server_reply = response.body.to_s
        
        if server_reply.include?("BANNED")
             @@is_licensed = false
             @@license_message = "تم حظر هذا السيريال (مخالفة الشروط)"
             return false 
        elsif server_reply.include?("DEVICE_MISMATCH")
             @@is_licensed = false
             @@license_message = "هذا السيريال مسجل لجهاز آخر"
             return false
        else; return true; end
      rescue; return true; end
    end

    # 🔥 دالة فحص الـ Token والـ Hash (الجزء المعقد من الحماية) 🔥
    def self.check_online_by_token(full_response)
      validity = false
      current_hwid = self.get_hwid
      @@hwid = current_hwid
      
      if full_response.nil? || !full_response.start_with?("VALID|")
          @@is_licensed = false; @@license_message = "ملف الترخيص تالف"; validity = false
      else
          begin
            parts = full_response.split("|")
            server_hash = parts[1]
            local_hash = Digest::SHA256.hexdigest(current_hwid + SECRET_KEY)
            if server_hash == local_hash
              @@is_licensed = true; @@license_message = "نسخة أصلية مفعلة"; validity = true
            else
              @@is_licensed = false; @@license_message = "الجهاز غير مطابق"; validity = false
            end
          rescue
            @@is_licensed = false; @@license_message = "خطأ في البيانات"; validity = false
          end 
      end
      validity
    end

    # 🔥 دالة التحقق الشامل (تستدعي الفحص المعقد + فحص السيرفر) 🔥
    def self.run_auth_check
      token = self.read_registry_key('ActivationToken')
      saved_serial = self.read_registry_key('UserSerial')
      @@serial_number = saved_serial ? saved_serial : "غير مسجل"
      if token.nil? || token.empty?
        @@is_licensed = false; @@license_message = "النسخة غير مفعلة"; return false
      end
      # 1. التحقق المحلي (الـ Hash)
      local_check = self.check_online_by_token(token)
      if local_check
         # 2. التحقق الخارجي (السيرفر)
         online_check = self.force_server_check(@@serial_number, @@hwid)
         return online_check
      else; return false; end
    end

    # 3.1 نافذة معلومات الترخيص (باقية كما هي)
    def self.show_license_info
      # 🔥 هام: عند فتح حالة النسخة، يتم التحقق الشامل أولاً 🔥
      self.run_auth_check 
      ui_state = "error"; ui_icon = "✖"; ui_title = "النسخة غير مفعلة"; ui_desc = @@license_message
      if @@is_licensed
        ui_state = "success"; ui_icon = "✔"; ui_title = "نسخة أصلية مفعلة"; ui_desc = "شكراً لاستخدامك Click & Cut Pro"
      elsif @@license_message.include?("حظر") || @@license_message.include?("BANNED")
        ui_state = "banned"; ui_icon = "🚫"; ui_title = "تم حظر النسخة!"; ui_desc = "تم إيقاف هذا الترخيص بسبب مخالفة شروط الاستخدام."
      end
      
      options = {
          :dialog_title => "حالة الترخيص",
          :preferences_key => "CNC_License_Status",
          :scrollable => false, :resizable => false, :width => 400, :height => 460,
          :style => UI::HtmlDialog::STYLE_DIALOG
      }
      dialog = UI::HtmlDialog.new(options)
      
      html_content = <<-HTML
      <!DOCTYPE html>
      <html dir="rtl">
      <head>
          <meta charset="UTF-8">
          <style>
              body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f4f6f9; margin: 0; display: flex; justify-content: center; align-items: center; height: 100vh; }
              .card { background: white; width: 100%; max-width: 320px; padding: 30px; border-radius: 16px; box-shadow: 0 10px 30px rgba(0,0,0,0.08); text-align: center; border: 1px solid #e1e4e8; }
              .icon-circle { width: 80px; height: 80px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 40px; color: white; margin: 0 auto 20px auto; }
              .success { background: linear-gradient(135deg, #2ecc71, #27ae60); box-shadow: 0 6px 20px rgba(46, 204, 113, 0.3); }
              .error { background: linear-gradient(135deg, #e74c3c, #c0392b); box-shadow: 0 6px 20px rgba(231, 76, 60, 0.3); }
              .banned { background: linear-gradient(135deg, #2c3e50, #000000); box-shadow: 0 6px 20px rgba(0, 0, 0, 0.4); }
              h2 { margin: 5px 0 10px 0; color: #2c3e50; font-size: 24px; font-weight: 700; }
              p.status-msg { color: #7f8c8d; font-size: 14px; margin-bottom: 25px; line-height: 1.5; font-weight: 500; }
              .info-box { background: #f8f9fa; padding: 12px; border-radius: 8px; border: 1px dashed #ced4da; margin-bottom: 12px; text-align: center; }
              .info-label { font-size: 11px; color: #95a5a6; display: block; margin-bottom: 4px; font-weight: 600; text-transform: uppercase; }
              .info-value { font-family: 'Consolas', monospace; font-size: 14px; color: #34495e; font-weight: bold; direction: ltr; display: block; }
              .btn { background: #34495e; color: white; border: none; padding: 12px 35px; border-radius: 50px; cursor: pointer; font-size: 15px; font-weight: 600; transition: all 0.3s; margin-top: 15px; box-shadow: 0 4px 10px rgba(52, 73, 94, 0.2); }
              .btn:hover { background: #2c3e50; transform: translateY(-2px); }
              .version-tag { font-size:10px; color:#bdc3c7; margin-top:15px; }
          </style>
      </head>
      <body>
          <div class="card">
              <div class="icon-circle #{ui_state}">#{ui_icon}</div>
              <h2>#{ui_title}</h2>
              <p class="status-msg">#{ui_desc}</p>
              <div class="info-box" style="background: #eef2f5;">
                  <span class="info-label">سيريال التفعيل</span>
                  <span class="info-value">#{@@serial_number}</span>
              </div>
              <div class="info-box">
                  <span class="info-label">معرف الجهاز (ID)</span>
                  <span class="info-value">#{@@hwid}</span>
              </div>
              <div class="version-tag">Version: #{ClickAndCut::CURRENT_VERSION}</div>
              <button class="btn" onclick="window.location='skp:close'">إغلاق</button>
          </div>
      </body>
      </html>
      HTML
      
      dialog.set_html(html_content)
      dialog.add_action_callback("close") { dialog.close }
      dialog.center; dialog.show
    end
  end

  # ==========================================================================
  # 🌍 وحدة المجتمع (لم تتغير)
  # ==========================================================================
  module Community
    COMMUNITY_URL = "http://cnc-api.atwebpages.com/cnc_api/community_page.php"
    
    def self.check_notification_status
      last_seen_id = Sketchup.read_default("ClickAndCut_Pro", "last_seen_news_id", 0).to_i
      server_news_id = 0
      begin
         if ClickAndCut::Updater.class_variable_get(:@@server_data)
           server_news_id = ClickAndCut::Updater.class_variable_get(:@@server_data)["news_id"].to_i
         else
           uri = URI(ClickAndCut::UPDATE_API_URL)
           uri.query = URI.encode_www_form({:nocache => Time.now.to_i})
           data = JSON.parse(Net::HTTP.get(uri))
           server_news_id = data["news_id"].to_i
         end
      rescue; server_news_id = 0; end
      return (server_news_id > last_seen_id)
    end

    def self.open_community_window
      begin
         server_data = ClickAndCut::Updater.class_variable_get(:@@server_data)
         if server_data && server_data["news_id"]
            Sketchup.write_default("ClickAndCut_Pro", "last_seen_news_id", server_data["news_id"].to_i)
         end
      rescue; end

      options = {
        :dialog_title => "مجتمع Click & Cut",
        :preferences_key => "CNC_Community_Window",
        :scrollable => true, :resizable => true, :width => 1000, :height => 700,
        :style => UI::HtmlDialog::STYLE_DIALOG
      }
      dlg = UI::HtmlDialog.new(options)
      dlg.set_url(COMMUNITY_URL)
      dlg.center; dlg.show
    end
  end

  # ==========================================================================
  # 📂 وحدة المكتبة (LibraryBrowser)
  # ==========================================================================
  module LibraryBrowser
    PLUGIN_DIR = File.dirname(__FILE__).force_encoding("UTF-8")
    FAVORITES_FILE_PATH = File.join(PLUGIN_DIR, "favorites_data.json")
    @@thumbs_temp_dir = File.join(ENV['TEMP'] || ENV['TMPDIR'] || '/tmp', 'ClickAndCut_Thumbs_Cache')
    
    @@library_root_path = ""
    @@current_relative_path = ""
    @@favorites_list = []

    CIPHER_ALGO = 'AES-256-CBC'
    FILE_SECRET_KEY = ["a45df89g7h2j3k4l5m6n7o8p9q0r1s2t3u4v5w6x7y8z9a0b1c2d3e4f5g6h7i8j"].pack('H*') 
    FILE_FIXED_IV = ["f1e2d3c4b5a69788796a5b4c3d2e1f00"].pack('H*')
    
    # 🔥 دالة عرض الرسائل الاحترافية (جديدة) 🔥
    def self.show_update_status_dialog(is_success:, title:, message:, details:)
      
      icon = is_success ? "✔" : "❌"
      color = is_success ? "#2ecc71" : "#e74c3c"
      
      html_content = <<-HTML
      <!DOCTYPE html>
      <html dir="rtl">
      <head>
        <meta charset="UTF-8">
        <style>
          body { font-family: 'Segoe UI', sans-serif; background: #f8f9fa; padding: 20px; text-align: center; }
          .card { background: white; border-radius: 12px; padding: 30px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); border-top: 5px solid #{color}; }
          .icon { font-size: 50px; color: #{color}; margin-bottom: 10px; }
          h2 { color: #2c3e50; margin-top: 0; }
          .message { font-size: 16px; color: #555; margin: 15px 0 10px 0; line-height: 1.6; font-weight: bold; }
          .details { font-size: 13px; color: #7f8c8d; white-space: pre-wrap; margin-bottom: 25px; }
          .btn { padding: 10px 25px; border-radius: 6px; border: none; cursor: pointer; font-weight: bold; background: #{color}; color: white; margin-top: 15px; }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="icon">#{icon}</div>
          <h2>#{title}</h2>
          <div class="message">#{message}</div>
          <div class="details">#{details}</div>
          <button class="btn" onclick="window.location='skp:close_dialog'">إغلاق</button>
        </div>
      </body>
      </html>
      HTML

      d = UI::HtmlDialog.new({:dialog_title => title, :width => 400, :height => 380, :style => UI::HtmlDialog::STYLE_DIALOG})
      d.set_html(html_content); d.center
      d.add_action_callback("close_dialog") { d.close }
      d.show
    end
    
    def self.check_integrity(file_path)
        return false unless File.exist?(file_path)
        content = File.read(file_path, mode: "rb")
        current_hash = Digest::SHA256.hexdigest(content)
        return current_hash == ClickAndCut::UI_HASH
    end

    def self.open_browser_window
        # 🔥 خطوة الأمان الجديدة: التحقق القسري من السيرفر عند كل محاولة لفتح المكتبة 🔥
        Sketchup.set_status_text("جاري التحقق من الترخيص... ")
        ClickAndCut::Protection.run_auth_check
        Sketchup.set_status_text("")
        
        if ClickAndCut::Protection.is_licensed? == false
          ClickAndCut::Protection.show_license_info
          return
        end
        # 🔥 نهاية التحقق القسري 🔥
        
        # ----------------------------------------------------
        # المنطق المتبقي (فتح المكتبة، بعد التحقق)
        # ----------------------------------------------------
        
        has_update = false
        begin
           has_update = ClickAndCut::Updater.check_for_update_availability
        rescue
           has_update = false
        end

        if ClickAndCut::Updater.is_restart_required?
           # 🔥 تم التعديل: استبدال UI.messagebox بنافذة HTML 🔥
           self.show_update_status_dialog(
             is_success: false, 
             title: "تنبيه هام", 
             message: "تم تحميل تحديثات جديدة.", 
             details: "يجب إغلاق SketchUp تماماً وإعادة تشغيله."
           )
           return 
        end

        internal_path = File.join(File.dirname(__FILE__), 'Library_Content')
        @@library_root_path = internal_path.force_encoding("UTF-8")
        h_path = File.join(File.dirname(__FILE__), 'browser_ui.html')

        if File.directory?(@@library_root_path)
           self.load_favorites
           Dir.mkdir(@@thumbs_temp_dir) unless Dir.exist?(@@thumbs_temp_dir)
           
           # 🔥 تم الإصلاح: استدعاء دالة فحص الحماية 🔥
           if File.exist?(h_path) && !self.check_integrity(h_path)
               self.show_update_status_dialog(
                 is_success: false, 
                 title: "خطأ في ملف الواجهة!", 
                 message: "تم الكشف عن تعديل غير مصرح به في ملف الواجهة (browser_ui.html).", 
                 details: "لن يتم فتح المكتبة لضمان سلامة البرنامج."
               )
               return
           end
           # 🔥 نهاية الإصلاح 🔥
           
           d_opts = {
             :dialog_title => " Click & Cut Pro ",
             :preferences_key => "CNC_Library_UI_V2",
             :scrollable => false, :resizable => true, :width => 1200, :height => 800,
             :style => UI::HtmlDialog::STYLE_DIALOG
           }
           
           dlg = UI::HtmlDialog.new(d_opts)
           
           if File.exist?(h_path)
             dlg.set_file(h_path)
             
             dlg.add_action_callback("requestRootFolders") do |ctx| 
                 self.send_subfolders_to_sidebar(dlg, "") 
                 show_news_dot = ClickAndCut::Community.check_notification_status
                 dlg.execute_script("showCommunityNotification(#{show_news_dot});") 
                 dlg.execute_script("showUpdateNotification(#{has_update});")
             end

             dlg.add_action_callback("openCommunityPage") do |ctx|
                 ClickAndCut::Community.open_community_window
                 dlg.execute_script("showCommunityNotification(false);") 
             end

             dlg.add_action_callback("checkForUpdatesUI") do |ctx|
                 ClickAndCut::Updater.manual_check_ui
             end

             dlg.add_action_callback("requestSubfolders") { |ctx, rel| self.send_subfolders_to_sidebar(dlg, rel) }
             dlg.add_action_callback("requestNavigate") { |ctx, folder|
               rel = folder.nil? ? "" : folder
               target = File.join(@@library_root_path, rel)
               if File.directory?(target)
                   @@current_relative_path = rel
                   self.send_content_to_ui(dlg, target)
               else
                   @@current_relative_path = ""
                   self.send_content_to_ui(dlg, @@library_root_path)
               end
             }
             dlg.add_action_callback("requestFavorites") { |ctx| self.send_favorites_to_ui(dlg) }
             dlg.add_action_callback("toggleFavorite") { |ctx, path| self.toggle_favorite(dlg, path) }
             dlg.add_action_callback("requestBack") { |ctx|
               @@current_relative_path = File.dirname(@@current_relative_path)
               @@current_relative_path = "" if @@current_relative_path == "."
               self.send_content_to_ui(dlg, File.join(@@library_root_path, @@current_relative_path))
             }
             
             dlg.add_action_callback("importComponent") { |ctx, rel|
               if ClickAndCut::Protection.is_licensed?
                   full = File.join(@@library_root_path, rel)
                   unless File.exist?(full)
                       poss = File.join(@@library_root_path, @@current_relative_path, rel + ".cnc")
                       full = File.exist?(poss) ? poss : File.join(@@library_root_path, @@current_relative_path, rel + ".skp")
                   end

                   if File.exist?(full)
                       if full.downcase.end_with?('.cnc')
                           temp = File.join(@@thumbs_temp_dir, "tmp_#{Time.now.to_i}.skp")
                           begin; dec = OpenSSL::Cipher.new(CIPHER_ALGO); dec.decrypt; dec.key = FILE_SECRET_KEY; dec.iv = FILE_FIXED_IV
                           File.open(temp, 'wb') { |o| File.open(full, 'rb') { |i| while b=i.read(4096); o.write(dec.update(b)); end; o.write(dec.final) } }
                           self.do_import_skp(temp); rescue; UI.messagebox("خطأ فك التشفير"); ensure; File.delete(temp) if File.exist?(temp); end
                       else; self.do_import_skp(full); end
                   end
               else
                   ClickAndCut::Protection.show_license_info
               end
             }
             
             dlg.add_action_callback("requestRefreshCurrentPath") { |ctx|
               if @@current_relative_path == "FAVORITES_MODE" then self.send_favorites_to_ui(dlg)
               else self.send_content_to_ui(dlg, File.join(@@library_root_path, @@current_relative_path)) end
             }
             dlg.add_action_callback("requestGlobalSearch") { |ctx, q| self.perform_global_search(dlg, q) }
             dlg.add_action_callback("requestClearCache") do |ctx|
               FileUtils.rm_rf(@@thumbs_temp_dir) if File.directory?(@@thumbs_temp_dir); Dir.mkdir(@@thumbs_temp_dir)
               self.send_subfolders_to_sidebar(dlg, ""); self.send_content_to_ui(dlg, @@library_root_path)
             end

             dlg.center; dlg.show
           else
             UI.messagebox("ملف الواجهة مفقود!")
           end
        else
           UI.messagebox("خطأ: لم يتم العثور على مجلد المكتبة.", MB_OK)
        end
    end

    def self.do_import_skp(path); m=Sketchup.active_model; m.start_operation("Add",true); m.import(path); m.commit_operation; end
    def self.load_favorites; if File.exist?(FAVORITES_FILE_PATH); begin; @@favorites_list = JSON.parse(File.read(FAVORITES_FILE_PATH, mode: "r:UTF-8")); rescue; @@favorites_list = []; end; else; @@favorites_list = []; end; end
    def self.save_favorites; begin; File.write(FAVORITES_FILE_PATH, JSON.pretty_generate(@@favorites_list), mode: "w:UTF-8"); rescue; end; end
    def self.toggle_favorite(dlg, path); if @@favorites_list.include?(path) then @@favorites_list.delete(path) else @@favorites_list.push(path) end; self.save_favorites; dlg.execute_script("updateFavoriteIcon('#{path.gsub("'", "\\'")}', #{@@favorites_list.include?(path)});"); end
    
    def self.send_favorites_to_ui(dlg)
       @@current_relative_path = "FAVORITES_MODE"; base = @@library_root_path.to_s.force_encoding("UTF-8"); list = []
       @@favorites_list.select! { |p| File.exist?(File.join(base, p)) || File.exist?(File.join(base, p.gsub('.skp', '.cnc'))) }; self.save_favorites
       @@favorites_list.each do |p|
         f = File.join(base, p.gsub('.skp', '.cnc')); f = File.join(base, p) unless File.exist?(f)
         if File.exist?(f); n = File.basename(f, ".*"); list << { :name => n, :type => "file", :thumb_url => self.get_thumbnail_url(f, n), :full_path_relative => p, :is_favorite => true }; end
       end
       dlg.execute_script("updateMainContent(#{list.sort_by{|i| i[:name]}.to_json}, '⭐ المفضلة', false, true, true);")
    end

    def self.send_subfolders_to_sidebar(dlg, par)
      base = @@library_root_path.to_s.force_encoding("UTF-8"); tgt = File.join(base, par); return unless File.directory?(tgt)
      l = Dir.glob(File.join(tgt, "*")).select{|f| File.directory?(f) && !File.basename(f).start_with?('.')}.map{|f| { :name => File.basename(f).force_encoding("UTF-8"), :path => Pathname.new(f).relative_path_from(Pathname.new(base)).to_s.force_encoding("UTF-8") }}
      dlg.execute_script("populateSubfolders('#{par.gsub("'", "\\'")}', #{l.sort_by{|i| i[:name]}.to_json});")
    end

    def self.send_content_to_ui(dlg, tgt)
      safe = File.expand_path(tgt.to_s.force_encoding("UTF-8")); base = File.expand_path(@@library_root_path.to_s.force_encoding("UTF-8")); return unless File.directory?(safe)
      # 🔥 تم الإصلاح: إزالة المسافات الزائدة حول Pathname.new(base)
      curr = (safe == base) ? "" : Pathname.new(safe).relative_path_from(Pathname.new(base)).to_s.force_encoding("UTF-8"); list = []
      Dir.glob(File.join(safe, "*")).each do |p|
          n = File.basename(p).force_encoding("UTF-8"); next if n.start_with?('.') || n == 'Thumbs.db'
          if File.directory?(p); list << { :name => n, :type => "folder", :path => Pathname.new(p).relative_path_from(Pathname.new(base)).to_s.force_encoding("UTF-8") }
          elsif n.downcase =~ /\.(cnc|skp)$/; bn = File.basename(n, ".*"); rel = Pathname.new(p).relative_path_from(Pathname.new(base)).to_s.force_encoding("UTF-8")
             skp_rel = rel.gsub('.cnc', '.skp')
             list << { :name => bn, :type => "file", :thumb_url => self.get_thumbnail_url(p, bn), :full_path_relative => rel, :is_favorite => @@favorites_list.include?(skp_rel) }
          end
      end
      dlg.execute_script("updateMainContent(#{list.sort_by{|i| [i[:type]=="folder"?0:1, i[:name]]}.to_json}, '#{(safe==base)?"الرئيسية":File.basename(safe)}', '#{curr.gsub("'", "\\'")}', #{safe==base});")
    end

    def self.perform_global_search(dlg, q)
       base = @@library_root_path.to_s.force_encoding("UTF-8"); qu = q.to_s.force_encoding("UTF-8").downcase; res = []
       ['.cnc', '.skp'].each do |ext|
         Dir.glob(File.join(base, "**", "*#{qu}*#{ext}"), File::FNM_CASEFOLD).each do |p|
             n = File.basename(p).force_encoding("UTF-8"); next if n.start_with?('.'); bn = File.basename(n, ".*"); next if res.any?{|r| r[:name] == bn}
             act = Pathname.new(p).relative_path_from(Pathname.new(base)).to_s.force_encoding("UTF-8")
             res << { :name => bn, :type => "file", :thumb_url => self.get_thumbnail_url(p, bn), :full_path_relative => act, :is_favorite => @@favorites_list.include?(act.gsub('.cnc', '.skp')) }
         end
       end
       dlg.execute_script("updateMainContent(#{res.sort_by{|i| i[:name]}.to_json}, 'نتائج البحث عن: #{qu}', false, true);")
    end

    def self.get_thumbnail_url(p, n)
       tn = "#{n}_#{File.mtime(p).to_i}.png"; tp = File.join(@@thumbs_temp_dir, tn)
       unless File.exist?(tp)
         Dir.glob(File.join(@@thumbs_temp_dir, "#{name}_*.png")).each{|f| File.delete(f)}; if p.downcase.end_with?('.cnc')
             tmp = File.join(@@thumbs_temp_dir, "t_#{Time.now.to_i}.skp"); begin; dec=OpenSSL::Cipher.new(CIPHER_ALGO); dec.decrypt; dec.key=FILE_SECRET_KEY; dec.iv=FILE_FIXED_IV; File.open(tmp,'wb'){|o| File.open(p,'rb'){|i| while b=i.read(4096); o.write(dec.update(b)); end; o.write(dec.final)}}; Sketchup.save_thumbnail(tmp, tp); rescue; ensure; File.delete(tmp) if File.exist?(tmp); end
         else; Sketchup.save_thumbnail(p, tp); end
       end
       return "file:///" + tp.gsub("\\", "/")
    end

    unless file_loaded?(__FILE__)
      ClickAndCut::Protection.run_auth_check
      cmd_open = UI::Command.new("فتح المكتبة") { self.open_browser_window }
      cmd_open.tooltip = "Click & Cut Pro - المكتبة"
      icon_s = File.join(File.dirname(__FILE__), 'icons', 'icon_small.png'); icon_l = File.join(File.dirname(__FILE__), 'icons', 'icon_large.png')
      if File.exist?(icon_s) && File.exist?(icon_l); cmd_open.small_icon = icon_s; cmd_open.large_icon = icon_l; end

      cmd_community = UI::Command.new("مجتمع Click & Cut") { ClickAndCut::Community.open_community_window }
      cmd_community.tooltip = "أخبار وعروض السوق"
      icon_community_s = File.join(File.dirname(__FILE__), 'icons', 'small_community_icon.png'); icon_community_l = File.join(File.dirname(__FILE__), 'icons', 'large_community_icon.png')
      if File.exist?(icon_community_s) && File.exist?(icon_community_l); cmd_community.small_icon = icon_community_s; cmd_community.large_icon = icon_community_l; end

      cmd_status = UI::Command.new("حالة النسخة") { ClickAndCut::Protection.show_license_info }
      cmd_status.tooltip = "معلومات الترخيص"
      status_icon_s = File.join(File.dirname(__FILE__), 'icons', 'status_small.png'); status_icon_l = File.join(File.dirname(__FILE__), 'icons', 'status_large.png')
      if File.exist?(status_icon_s) && File.exist?(status_icon_l); cmd_status.small_icon = status_icon_s; cmd_status.large_icon = status_icon_l; end
      
      toolbar = UI::Toolbar.new "Click & Cut Tools"
      toolbar.add_item cmd_open; toolbar.add_item cmd_community; toolbar.add_separator; toolbar.add_item cmd_status
      toolbar.show unless toolbar.get_last_state == TB_VISIBLE
      
      menu = UI.menu("Extensions"); sub = menu.add_submenu("Click and cut"); sub.add_item(cmd_open); sub.add_item(cmd_community); sub.add_item(cmd_status)
      file_loaded(__FILE__)
    end
  end
end
