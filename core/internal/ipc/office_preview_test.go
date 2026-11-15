package ipc

import (
	"archive/zip"
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestOfficePreviewSandboxedConversion(t *testing.T) {
	runtimeRoot := os.Getenv("FJORD_TEST_OFFICE_RUNTIME_ROOT")
	converter := os.Getenv("FJORD_TEST_OFFICE_CONVERTER")
	if runtimeRoot == "" || converter == "" {
		t.Skip("set FJORD_TEST_OFFICE_RUNTIME_ROOT and FJORD_TEST_OFFICE_CONVERTER for the optional LibreOffice integration test")
	}
	t.Setenv("FJORD_OFFICE_RUNTIME_ROOT", runtimeRoot)
	t.Setenv("FJORD_OFFICE_CONVERTER", converter)
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	tools, ok := officeConverter()
	require.True(t, ok)

	path := filepath.Join(t.TempDir(), "fixture.docx")
	file, err := os.Create(path)
	require.NoError(t, err)
	archive := zip.NewWriter(file)
	for name, body := range map[string]string{
		"[Content_Types].xml": `<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>`,
		"_rels/.rels":         `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>`,
		"word/document.xml":   `<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Office preview test</w:t></w:r></w:p><w:sectPr/></w:body></w:document>`,
	} {
		member, err := archive.Create(name)
		require.NoError(t, err)
		_, err = member.Write([]byte(body))
		require.NoError(t, err)
	}
	require.NoError(t, archive.Close())
	require.NoError(t, file.Close())

	source, err := os.Open(path)
	require.NoError(t, err)
	defer source.Close()
	info, err := source.Stat()
	require.NoError(t, err)
	mime := officeMimeFromZip(source, info.Size())
	require.Equal(t, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", mime)
	result, err := convertOffice(context.Background(), source, path, info, mime, tools)
	require.NoError(t, err)
	require.True(t, validOfficePDF(result.Path))

	cached, err := convertOffice(context.Background(), source, path, info, mime, tools)
	require.NoError(t, err)
	require.Equal(t, result.Path, cached.Path)
}
