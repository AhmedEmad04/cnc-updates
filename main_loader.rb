#Encoding: UTF-8
# ==============================================================================
# ملف: main_loader.rb (النسخة النهائية النظيفة)
# الوظيفة: النسخة الكاملة (الكود الأصلي + وحدة التحديث المدمجة)
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
# تم حذف استدعاء ملف updater.rbe/rb

module ClickAndCut

  # 1. تعريف رقم الإصدار الحالي
  CURRENT_VERSION = "2.0.1"
  
  # رابط ملف التحديث على السيرفر
  UPDATE_API_URL = "http://cnc-api.atwebpages.com/cnc_api/version.json"

  # 2. بصمة ملف الواجهة (ثابتة)
  UI_HASH = "0b161acf3e2aee885f86bd4799d773b156b2767dcbc83634848136382214c282"

  # ==========================================================================
  # 🔄 وحدة التحديث (Updater Module) - (مدمجة ومصححة) 🔄
  # ==========================================================================
  module Updater

    API_URL = ClickAndCut::UPDATE_API_URL 
    @@restart_required = false

    def self.is_restart_required?
      @@restart_required
    end

    def self.download_silent_update
      begin
        uri = URI(API_URL)
        uri.query = URI.encode_www_form({:nocache => Time.now.to_i})
        response = Net::HTTP.get(uri)
        data = JSON.parse(response)

        server_ver = data["version"].to_s.strip
        local_ver = ClickAndCut::CURRENT_VERSION.to_s.strip

        if server_ver != local_ver
            files_list = data["files_to_update"]
            
            if files_list.is_a?(Array) && !files_list.empty?
                
                UI.messagebox("يوجد تحديث هام (v#{server_ver})! سيتم تحميل #{files_list.length} ملفات الآن.. يرجى الانتظار قليلاً.", MB_OK)
                
                download_succeeded = true
                folder_path = File.dirname(__FILE__)
                
                files_list.each do |file_info|
                    file_name = file_info["name"].to_s
                    download_link = file_info["url"].to_s
                    
                    next unless download_link.start_with?('http')
                    
                    target_file = File.join(folder_path, "#{file_name}.new") 
                    
                    File.open(target_file, "wb") do |file|
                      file.write Net::HTTP.get(URI(download_link))
                    end
                    
                    unless File.size?(target_file).to_i > 0
                        download_succeeded = false
                        UI.messagebox("❌ فشل تحميل الملف: #{file_name}. يرجى محاولة التحديث لاحقاً.")
                        break
                    end
                end 
                
                if download_succeeded
                    @@restart_required = true
                    UI.messagebox("✅ تم تحميل التحديثات بالكامل!\n\nمن فضلك أغلق SketchUp تماماً وأعد تشغيله لتثبيت التحديث الجديد.", MB_OK)
                else
                    files_list.each do |file_info|
                        temp_file = File.join(folder_path, "#{file_info["name"].to_s}.new")
                        File.delete(temp_file) if File.exist?(temp_file)
                    end
                end 
                
                return true
            end 
        else 
            UI.messagebox("نسختك محدثة بالفعل (v#{local_ver})")
            return false
        end 

      rescue => e
        UI.messagebox("حدث خطأ أثناء الاتصال أو التحديث: #{e.message}")
        
        if data && data["files_to_update"].is_a?(Array)
             data["files_to_update"].each do |file_info|
                 temp_file = File.join(File.dirname(__FILE__), "#{file_info["name"].to_s}.new")
                 File.delete(temp_file) if File.exist?(temp_file)
             end
        end
        return false
      end 
    end

  end 
  # ==========================================================================

  # ==========================================================================
  # 🔒 وحدة الحماية (Protection Module)
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

    # 1. تحديد اسم المجلد
    def self.get_sketchup_reg_name
        v_str = Sketchup.version.split('.')[0]
        v_int = v_str.to_i
        final_name = "SketchUp #{v_int}"
        if v_int == 23; final_name = "SketchUp 2023"; end
        if v_int == 24; final_name = "SketchUp 2024"; end
        final_name
    end
    
    # 2. قراءة مفتاح من الريجستري
    def self.read_registry_key(key_name)
      val = nil
      begin
        folder = self.get_sketchup_reg_name
        key_path = "Software\\SketchUp\\#{folder}\\ClickAndCut_Pro"
        Win32::Registry::HKEY_CURRENT_USER.open(key_path) do |reg|
          val = reg[key_name]
        end
      rescue
        val = nil
      end
      val
    end

    # 3. قراءة الهاردوير
    def self.get_hwid
      id = "UNKNOWN_ID"
      begin
        file_system = WIN32OLE.new('Scripting.FileSystemObject')
        drive = file_system.GetDrive('C:')
        id = drive.SerialNumber.to_s.strip
      rescue
        id = "UNKNOWN_ID"
      end
      id
    end

    # 4. فحص الحظر أونلاين (مصححة)
    def self.force_server_check(serial, current_hwid)
      return true if serial.nil? || serial == "غير مسجل"
      
      begin
        uri = URI("#{API_URL}?serial=#{serial}&hwid=#{current_hwid}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 3 
        http.read_timeout = 3
        
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
        else
             return true
        end
      rescue
         return true
      end
    end

    # 5. التحقق المحلي (مصححة)
    def self.check_online_by_token(full_response)
      validity = false
      current_hwid = self.get_hwid
      @@hwid = current_hwid
      
      if full_response.nil? || !full_response.start_with?("VALID|")
          @@is_licensed = false
          @@license_message = "ملف الترخيص تالف"
          validity = false
      else
          begin
            parts = full_response.split("|")
            server_hash = parts[1]
            local_hash = Digest::SHA256.hexdigest(current_hwid + SECRET_KEY)

            if server_hash == local_hash
              @@is_licensed = true
              @@license_message = "نسخة أصلية مفعلة"
              validity = true
            else
              @@is_licensed = false
              @@license_message = "الجهاز غير مطابق (نقل غير مسموح)"
              validity = false
            end
          rescue
            @@is_licensed = false
            @@license_message = "خطأ في البيانات"
            validity = false
          end 
      end
      validity
    end

    # 6. التشغيل الرئيسي
    def self.run_auth_check
      token = self.read_registry_key('ActivationToken')
      saved_serial = self.read_registry_key('UserSerial')
      @@serial_number = saved_serial ? saved_serial : "غير مسجل"

      if token.nil? || token.empty?
        @@is_licensed = false
        @@license_message = "النسخة غير مفعلة"
        return false
      end

      local_check = self.check_online_by_token(token)
      
      if local_check
         online_check = self.force_server_check(@@serial_number, @@hwid)
         return online_check
      else
         return false
      end
    end

    # 7. واجهة المستخدم (النسخة الذكية)
    def self.show_license_info
      self.run_auth_check 
      
      # منطق تحديد شكل الصفحة
      ui_state = "error"
      ui_icon = "✖"
      ui_title = "النسخة غير مفعلة"
      ui_desc = @@license_message

      if @@is_licensed
        ui_state = "success"
        ui_icon = "✔"
        ui_title = "نسخة أصلية مفعلة"
        ui_desc = "شكراً لاستخدامك Click & Cut Pro"
      elsif @@license_message.include?("حظر") || @@license_message.include?("BANNED")
        ui_state = "banned" 
        ui_icon = "🚫"
        ui_title = "تم حظر النسخة!"
        ui_desc = "تم إيقاف هذا الترخيص بسبب مخالفة شروط الاستخدام."
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
              
              /* الأنماط المختلفة للحالة */
              .success { background: linear-gradient(135deg, #2ecc71, #27ae60); box-shadow: 0 6px 20px rgba(46, 204, 113, 0.3); }
              .error { background: linear-gradient(135deg, #e74c3c, #c0392b); box-shadow: 0 6px 20px rgba(231, 76, 60, 0.3); }
              .banned { background: linear-gradient(135deg, #2c3e50, #000000); box-shadow: 0 6px 20px rgba(0, 0, 0, 0.4); } /* لون أسود للحظر */
              
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
      dialog.center
      dialog.show
    end
  end

  # ==========================================================================
  # 🌍 وحدة المجتمع والتحديثات (Community Module)
  # ==========================================================================
  module Community
    COMMUNITY_URL = "http://cnc-api.atwebpages.com/cnc_api/community_page.php"
    @@update_info = nil

    def self.open_community_window
        options = {
          :dialog_title => "مجتمع Click & Cut",
          :preferences_key => "CNC_Community_Window",
          :scrollable => true, :resizable => true, :width => 1000, :height => 700,
          :style => UI::HtmlDialog::STYLE_DIALOG
        }
        dlg = UI::HtmlDialog.new(options)
        
        # توجيه النافذة لصفحة الويب
        dlg.set_url(COMMUNITY_URL)
        
        dlg.center
        dlg.show
    end
    
    # دالة التحقق من التحديثات (نواة المستقبل)
    def self.check_for_updates
        begin
          uri = URI(ClickAndCut::UPDATE_API_URL)
          # إضافة رقم عشوائي لمنع الكاش وضمان أحدث نسخة
          uri.query = URI.encode_www_form({:nocache => Time.now.to_i}) 
          response = Net::HTTP.get(uri)
          data = JSON.parse(response)
          
          server_ver = data["version"].to_s.strip
          local_ver = ClickAndCut::CURRENT_VERSION.to_s.strip
          
          if server_ver != local_ver
             @@update_info = data
             return true # يوجد تحديث
          end
        rescue
          return false
        end
        return false
    end

    def self.get_update_data; @@update_info; end
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
    
    # دالة للتحقق من سلامة الملفات
    def self.check_integrity(file_path)
        return false unless File.exist?(file_path)
        content = File.read(file_path, mode: "rb")
        current_hash = Digest::SHA256.hexdigest(content)
        return current_hash == ClickAndCut::UI_HASH
    end

    def self.open_browser_window
        if ClickAndCut::Protection.is_licensed? == false
          ClickAndCut::Protection.show_license_info
        else
          
          # فحص هل يوجد تحديث معلق (Restart Required)؟
          if ClickAndCut::Updater.is_restart_required?
             UI.messagebox("⚠️ تنبيه هام ⚠️\n\nتم تحميل تحديثات جديدة.\nيجب إغلاق SketchUp تماماً وإعادة تشغيله لتثبيت التحديث.", MB_OK)
             return 
          end

          internal_path = File.join(File.dirname(__FILE__), 'Library_Content')
          @@library_root_path = internal_path.force_encoding("UTF-8")
          h_path = File.join(File.dirname(__FILE__), 'browser_ui.html')

          # فحص أمني: هل تم التلاعب بالواجهة؟
          if ClickAndCut::UI_HASH != "PASTE_YOUR_HASH_HERE" && !self.check_integrity(h_path)
             UI.messagebox("خطأ أمني: تم اكتشاف تعديل غير مصرح به في ملفات البرنامج.\nلن يعمل التطبيق لضمان حقوق الملكية.", MB_OK)
             return
          end

          if File.directory?(@@library_root_path)
             self.load_favorites
             Dir.mkdir(@@thumbs_temp_dir) unless Dir.exist?(@@thumbs_temp_dir)
             
             # تحديث المفتاح لتطبيق الحجم الجديد
             d_opts = {
               :dialog_title => " Click & Cut Pro ",
               :preferences_key => "ClickAndCut_Pro_UI_V2",
               :scrollable => false, :resizable => true, :width => 1200, :height => 800,
               :style => UI::HtmlDialog::STYLE_DIALOG
             }
             
             dlg = UI::HtmlDialog.new(d_opts)
             
             if File.exist?(h_path)
               dlg.set_file(h_path)
               
               # =====================================================
               # ربط دوال الـ Callback
               # =====================================================
               dlg.add_action_callback("requestRootFolders") do |ctx| 
                   self.send_subfolders_to_sidebar(dlg, "") 
                   dlg.execute_script("showCommunityNotification(true);") 
                   has_up = ClickAndCut::Community.check_for_updates
                   dlg.execute_script("showUpdateNotification(#{has_up});")
               end

               dlg.add_action_callback("openCommunityPage") do |ctx|
                   ClickAndCut::Community.open_community_window
               end

               dlg.add_action_callback("checkForUpdatesUI") do |ctx|
                   ClickAndCut::Updater.download_silent_update
               end

               # بقية دوال المكتبة الأصلية (كما هي بدون حذف)
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

               dlg.center
               dlg.show
             else
               UI.messagebox("ملف الواجهة مفقود!")
             end
          else
             UI.messagebox("خطأ: لم يتم العثور على مجلد المكتبة.", MB_OK)
          end
        end
    end

    def self.do_import_skp(path); m=Sketchup.active_model; m.start_operation("Add",true); m.import(path); m.commit_operation; end

    def self.load_favorites
      if File.exist?(FAVORITES_FILE_PATH); begin; @@favorites_list = JSON.parse(File.read(FAVORITES_FILE_PATH, mode: "r:UTF-8")); rescue; @@favorites_list = []; end; else; @@favorites_list = []; end
    end
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

      # 1. زر فتح المكتبة
      cmd_open = UI::Command.new("فتح المكتبة") { self.open_browser_window }
      cmd_open.tooltip = "Click & Cut Pro - المكتبة"
      icon_s = File.join(File.dirname(__FILE__), 'icons', 'icon_small.png')
      icon_l = File.join(File.dirname(__FILE__), 'icons', 'icon_large.png')
      if File.exist?(icon_s) && File.exist?(icon_l)
        cmd_open.small_icon = icon_s
        cmd_open.large_icon = icon_l
      end

      # 2. زر المجتمع (الجديد)
      cmd_community = UI::Command.new("مجتمع Click & Cut") { ClickAndCut::Community.open_community_window }
      cmd_community.tooltip = "أخبار وعروض السوق"
      cmd_community.status_bar_text = "تصفح آخر الأخبار وعروض الشركات الشريكة"

      icon_community_s = File.join(File.dirname(__FILE__), 'icons', 'small_community_icon.png')
      icon_community_l = File.join(File.dirname(__FILE__), 'icons', 'large_community_icon.png')

      # تم التصحيح لـ small_icon و large_icon
      if File.exist?(icon_community_s) && File.exist?(icon_community_l)
        cmd_community.small_icon = icon_community_s 
        cmd_community.large_icon = icon_community_l 
      end

      # 3. زر حالة النسخة
      cmd_status = UI::Command.new("حالة النسخة") { ClickAndCut::Protection.show_license_info }
      cmd_status.tooltip = "معلومات الترخيص"
      cmd_status.status_bar_text = "عرض حالة النسخة والسيريال"
      
      status_icon_s = File.join(File.dirname(__FILE__), 'icons', 'status_small.png')
      status_icon_l = File.join(File.dirname(__FILE__), 'icons', 'status_large.png')
      if File.exist?(status_icon_s) && File.exist?(status_icon_l)
        cmd_status.small_icon = status_icon_s
        cmd_status.large_icon = status_icon_l
      end
      
      # تجميع التولبار (بالترتيب الجديد)
      toolbar = UI::Toolbar.new "Click & Cut Tools"
      toolbar.add_item cmd_open
      toolbar.add_item cmd_community 
      toolbar.add_separator
      toolbar.add_item cmd_status
      toolbar.show unless toolbar.get_last_state == TB_VISIBLE
      
      # تجميع القائمة (بالترتيب الجديد)
      menu = UI.menu("Extensions")
      sub = menu.add_submenu("Click and cut")
      sub.add_item(cmd_open)
      sub.add_item(cmd_community) 
      sub.add_item(cmd_status)
      
      file_loaded(__FILE__)

    end

  end
end