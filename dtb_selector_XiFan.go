package main

import (
	"bufio"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type Option struct {
	Display string // 菜单展示名
	Real    string // consoles/<Real>
	Logo    string // consoles/logo/<...>/
}

var XiFanOptions = []Option{
	{Display: "XiFan Mymini", Real: "mymini", Logo: "logo/480P/"},
	{Display: "XiFan R36Max", Real: "r36max", Logo: "logo/720P/"},
	{Display: "XiFan R36Pro", Real: "r36pro", Logo: "logo/480P/"},
	{Display: "XiFan XF35H", Real: "xf35h", Logo: "logo/480P/"},
	{Display: "XiFan XF40H", Real: "xf40h", Logo: "logo/720P/"},
	{Display: "XiFan XF40V", Real: "dc40v", Logo: "logo/720P/"},
	{Display: "XiFan DC40V", Real: "dc40v", Logo: "logo/720P/"},
	{Display: "XiFan DC35V", Real: "dc35v", Logo: "logo/480P/"},
}

var stdinReader = bufio.NewReader(os.Stdin)

// ============== 文件复制函数 ==============
func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}

	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	defer out.Close()

	buf := make([]byte, 32*1024)
	_, err = io.CopyBuffer(out, in, buf)
	return err
}

func copyDirectory(src, dst string) error {
	info, err := os.Stat(src)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return fmt.Errorf("source is not a directory: %s", src)
	}
	return filepath.WalkDir(src, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		targetPath := filepath.Join(dst, rel)
		if d.IsDir() {
			return os.MkdirAll(targetPath, 0o755)
		}
		return copyFile(path, targetPath)
	})
}

// ============== 菜单交互 ==============
func prompt(msg string) (string, error) {
	fmt.Print(msg)
	line, err := stdinReader.ReadString('\n')
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(line), nil
}

func readIntChoice(msg string) (int, error) {
	for {
		resp, err := prompt(msg)
		if err != nil {
			return -1, err
		}
		l := strings.ToLower(resp)
		if l == "q" || l == "quit" || l == "exit" {
			return 0, nil
		}
		n, err := strconv.Atoi(resp)
		if err != nil {
			fmt.Println("请输入序号或输入 q 退出")
			continue
		}
		return n, nil
	}
}

func selectXiFan() (*Option, error) {
	fmt.Println("====== XIFAN 机型选择 ======")
	for i, opt := range XiFanOptions {
		fmt.Printf("  %d. %s\n", i+1, opt.Display)
	}
	fmt.Println("  0. 退出 (q 也可)")
	fmt.Println("===========================")

	for {
		choice, err := readIntChoice("选择序号: ")
		if err != nil {
			return nil, err
		}
		if choice == 0 {
			return nil, nil
		}
		if choice > 0 && choice <= len(XiFanOptions) {
			return &XiFanOptions[choice-1], nil
		}
		fmt.Println("无效选择，请重试。")
	}
}

// ============== 创建 .cn 文件 ==============
func createCNFile() error {
	f, err := os.Create(".cn")
	if err != nil {
		return err
	}
	defer f.Close()
	fmt.Println("已创建语言标记文件：.cn")
	return nil
}

// ============== 主流程 ==============
func main() {
	fmt.Println("DTB Selector (XIFAN Only)")
	fmt.Println("选择机型后，会复制对应 consoles/<机型> 和 logo 目录，并创建 .cn 文件。")
	fmt.Println()

	selected, err := selectXiFan()
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		return
	}
	if selected == nil {
		fmt.Println("已退出。")
		return
	}

	// 1. 复制机型目录
	srcPath := filepath.Join("consoles", selected.Real)
	if _, err := os.Stat(srcPath); os.IsNotExist(err) {
		fmt.Printf("未找到源目录: %s\n", srcPath)
		return
	}
	fmt.Printf("正在复制机型: %s => 当前目录\n", selected.Display)
	if err := copyDirectory(srcPath, "."); err != nil {
		fmt.Printf("复制机型失败: %v\n", err)
		return
	}

	// 2. 复制对应 LOGO
	if selected.Logo != "" {
		logoSrc := filepath.Join("consoles", selected.Logo)
		if _, err := os.Stat(logoSrc); err == nil {
			fmt.Printf("正在复制 LOGO: %s => 当前目录\n", selected.Logo)
			if err := copyDirectory(logoSrc, "."); err != nil {
				fmt.Printf("复制 LOGO 失败: %v\n", err)
				return
			}
		} else {
			fmt.Printf("提示：未找到 LOGO 目录：%s（跳过）\n", logoSrc)
		}
	}

	// 3. 创建 .cn 文件
	if err := createCNFile(); err != nil {
		fmt.Printf("创建 .cn 文件失败: %v\n", err)
		return
	}

	fmt.Printf("✅ 完成！已复制机型：%s (consoles/%s) + LOGO(%s)\n",
		selected.Display, selected.Real, selected.Logo)
}
