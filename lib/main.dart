import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            // 왼쪽 영역
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LeftPanel(),
              ),
            ),

            // 오른쪽 영역
            Container(
              width: 250,
              color: Colors.grey[100],
              child: RightPanel(),
            ),
          ],
        ),
      ),
    );
  }
}

class LeftPanel extends StatefulWidget {
  @override
  _LeftPanelState createState() => _LeftPanelState();
}

class _LeftPanelState extends State<LeftPanel> {

  //변수 
  final TextEditingController sourceController = TextEditingController(); //source directory
  final TextEditingController buildController = TextEditingController(); //build directory
  final TextEditingController projectNameController = TextEditingController(); //project name
  List<String> logs = []; //logs

  bool enableOpenGL = true;
  bool autoLink = true;

  //폴더 선택 함수
  Future<void> pickFolder(TextEditingController controller) async {
    String? path = await FilePicker.platform.getDirectoryPath();

    if (path != null) {
      setState(() {
        controller.text = path;
      });
    }
  }

  // 프로젝트 생성 함수 
  Future<void> createProject() async {
    String projectName = projectNameController.text;
    String sourceRoot = sourceController.text;
    String buildRoot = buildController.text;

    if (projectName.isEmpty || sourceRoot.isEmpty || buildRoot.isEmpty) {
      addLog("모든 값을 입력하세요");
      return;
    }

    try {
      String projectPath = p.join(sourceRoot, projectName);
      String srcPath = p.join(projectPath, 'src');
      String buildPath = p.join(buildRoot, projectName, 'build');
      String externalPath = p.join(projectPath, 'external');

      await Directory(srcPath).create(recursive: true);
      await Directory(buildPath).create(recursive: true);
      await Directory(externalPath).create(recursive: true);
      
      addLog("프로젝트 폴더 생성 완료");

      // 1. GDM 다운로드
      addLog("GDM 라이브러리 통합 관리자 다운로드 중...");
      Directory gdmDir = Directory(p.join(externalPath, 'gdm'));

      if (!await gdmDir.exists()) {
        var result = await Process.run('git', [
          'clone',
          '-b', 'gdm',
          '--single-branch',
          'https://github.com/awidesky/gdm.git',
          gdmDir.path
        ]);
        addLog("GDM 다운로드 완료");
      } else {
        addLog("GDM 이미 존재 → 업데이트 생략");
      }

      //main.cpp 생성 
      File(p.join(srcPath, 'main.cpp')).writeAsStringSync('''
#include <glad/gl.h>
#include <GLFW/glfw3.h>
#include <iostream>

int main() {
  if (!glfwInit()) return -1;
  GLFWwindow* window = glfwCreateWindow(800, 600, "GDM Auto Project", NULL, NULL);
  if (!window) { glfwTerminate(); return -1; }
  glfwMakeContextCurrent(window);

  if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
      return -1;
  }

  while (!glfwWindowShouldClose(window)) {
      glClearColor(0.2f, 0.3f, 0.3f, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT);
      glfwSwapBuffers(window);
      glfwPollEvents();
  }
  glfwTerminate();
  return 0;
}
'''.trim());

      //CMakeLists.txt 생성
      File(p.join(projectPath, 'CMakeLists.txt')).writeAsStringSync('''
cmake_minimum_required(VERSION 3.10)
project($projectName)

set(CMAKE_CXX_STANDARD 17)

# GDM 프로젝트 포함
add_subdirectory(external/gdm)

if (MSVC)
    add_compile_options(/utf-8 /Zc:__cplusplus)
endif()

# 실행 파일 생성
add_executable($projectName src/main.cpp)

# 라이브러리 링크
target_link_libraries($projectName PRIVATE gdm)
'''.trim());

      addLog("프로젝트 구성 완료! 빌드를 시작합니다.");
      await runCMake(projectPath, buildPath);

    } catch (e) {
      addLog("에러 발생: $e");
    }
  }

  //로그 추가 함수
  void addLog(String message) {
    setState(() {
      logs.add(message);
    });
  }


  //CMake 실행 함수
  Future<void> runCMake(String projectPath, String buildPath) async {
    try {
      addLog("CMake 실행 시작");

      var result1 = await Process.run(
        'cmake',
        ['-S', projectPath, '-B', buildPath],
      );

      addLog(result1.stdout);
      addLog(result1.stderr);

      var result2 = await Process.run(
        'cmake',
        ['--build', buildPath, '--config', 'Debug'],
      );

      addLog(result2.stdout);
      addLog(result2.stderr);

      addLog("빌드 완료!");
    } catch (e) {
      addLog("에러 발생: $e");
    }
  }

  //위젯
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        //프로젝트 이름 입력
        Text("Project Name"),
        TextField(
          controller: projectNameController,
          decoration: InputDecoration(border: OutlineInputBorder()),
        ),
        // 경로 입력
        Text("Source Directory"),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: sourceController,
                decoration: InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            SizedBox(width: 10),
            ElevatedButton(
              onPressed: () => pickFolder(sourceController),
              child: Text("Browse"),
            ),
          ],
        ),
        SizedBox(height: 16),

        Text("Build Directory"),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: buildController,
                decoration: InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            SizedBox(width: 10),
            ElevatedButton(
              onPressed: () => pickFolder(buildController),
              child: Text("Browse"),
            ),
          ],
        ),
        SizedBox(height: 16),

        // 옵션
        Row(
          children: [
            Checkbox(
              value: enableOpenGL,
              onChanged: (value) {
                setState(() {
                  enableOpenGL = value!;
                });
              },
            ),
            Text("Enable OpenGL"),
            SizedBox(width: 20),
            Checkbox(
              value: autoLink,
              onChanged: (value) {
                setState(() {
                  autoLink = value!;  
                });
              },
            ),            
            Text("Auto Link Libraries"),
            ElevatedButton(
              onPressed: createProject,
              child: Text("Test"),
            ),
          ],
        ),

        SizedBox(height: 16),

        // 테이블 영역
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
            ),
            child: Center(child: Text("Cached Libraries Table")),
          ),
        ),
        //로그 영역
        Expanded(
          child: Container(
            color: Colors.black,
            child: ListView(
              children: logs.map((log) {
                return Text(
                  log,
                  style: TextStyle(color: Colors.green),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class RightPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ElevatedButton(
            onPressed: () {},
            child: Text("Configure"),
          ),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {},
            child: Text("Generate"),
          ),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {},
            child: Text("Build"),
          ),
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: () {},
            child: Text("Open Build Folder"),
          ),

          SizedBox(height: 30),

          // 프리셋
          Align(
            alignment: Alignment.centerLeft,
            child: Text("Preset Profiles"),
          ),

          SizedBox(height: 10),

          Container(
            padding: EdgeInsets.all(10),
            color: Colors.white,
            child: Text("OpenGL Basic Template"),
          ),
        ],
      ),
    );
  }
}


