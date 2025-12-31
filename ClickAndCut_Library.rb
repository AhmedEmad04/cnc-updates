#Encoding: UTF-8
require 'sketchup.rb'
require 'extensions.rb'
require 'fileutils' 

module ClickAndCut
  
  PLUGIN_DIR = File.dirname(__FILE__)
  LIB_FOLDER = File.join(PLUGIN_DIR, 'ClickAndCut_Library') 
  LOADER_FILE = File.join(PLUGIN_DIR, 'ClickAndCut_Library.rb') 
  
  begin
    files_to_check = Dir.glob(File.join(LIB_FOLDER, '**', '*.new'))
    
    loader_update = LOADER_FILE + ".new"
    files_to_check << loader_update if File.exist?(loader_update)

    files_to_check.each do |new_file_path|
      
      target_file_path = new_file_path.chomp('.new')
      
      begin
        if File.exist?(target_file_path)
          begin
             File.delete(target_file_path)
          rescue
             old_backup = target_file_path + ".old_ver"
             File.delete(old_backup) if File.exist?(old_backup)
             File.rename(target_file_path, old_backup)
          end
        end
        
        File.rename(new_file_path, target_file_path)
        
        puts "ClickAndCut Auto-Update: Success -> #{File.basename(target_file_path)}"
        
      rescue => e
        puts "ClickAndCut Auto-Update Error for #{File.basename(new_file_path)}: #{e.message}"
      end
    end
  rescue; end

  
  POSSIBLE_LOADERS = ['main.rbe', 'main.rbs', 'main.rb']
  
  target_loader = POSSIBLE_LOADERS.find { |f| File.exist?(File.join(LIB_FOLDER, f)) }
  target_loader = 'main.rb' if target_loader.nil?

  final_loader_path = File.join('ClickAndCut_Library', target_loader)

  EXTENSION = SketchupExtension.new('Click & Cut Pro', final_loader_path)
  EXTENSION.description = "Smart Library for SketchUp - الإصدار الاحترافي"
  EXTENSION.version     = "2.1.1" 
  EXTENSION.copyright   = "© 2025 Click & Cut"
  EXTENSION.creator     = "Ahmed Emad" 

  Sketchup.register_extension(EXTENSION, true)

end