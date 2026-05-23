import os

def merge_flutter_code():
    # Kiểm tra xem project nằm trong thư mục 'app' hay thư mục hiện tại
    base_dir = 'app' if os.path.exists('app/pubspec.yaml') else '.'
    lib_dir = os.path.join(base_dir, 'lib')
    pubspec = os.path.join(base_dir, 'pubspec.yaml')
    output_file = 'flutter_code.txt'
    
    with open(output_file, 'w', encoding='utf-8') as outfile:
        # Ghi file pubspec.yaml để AI biết bạn đang dùng thư viện gì
        if os.path.exists(pubspec):
            outfile.write(f"========== FILE: {pubspec} ==========\n\n")
            with open(pubspec, 'r', encoding='utf-8') as infile:
                outfile.write(infile.read())
            outfile.write("\n\n")

        # Đọc toàn bộ các file .dart trong thư mục lib
        if os.path.exists(lib_dir):
            for root, dirs, files in os.walk(lib_dir):
                for file in files:
                    if file.endswith('.dart'):
                        file_path = os.path.join(root, file)
                        outfile.write(f"========== FILE: {file_path} ==========\n\n")
                        try:
                            with open(file_path, 'r', encoding='utf-8') as infile:
                                outfile.write(infile.read())
                        except Exception as e:
                            outfile.write(f"[Lỗi đọc file: {e}]\n")
                        outfile.write("\n\n")
            print(f"Gộp code thành công! Hãy tải file '{output_file}' lên.")
        else:
            print(f"Không tìm thấy thư mục {lib_dir}!")

merge_flutter_code()