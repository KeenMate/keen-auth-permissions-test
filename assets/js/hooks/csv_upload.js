// CsvUpload hook — reads a CSV file on the client, pushes content to LiveView,
// and persists the chosen separator in localStorage.
const STORAGE_KEY = "csv_import_separator"

const CsvUpload = {
  mounted() {
    // Restore separator from localStorage
    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved) {
      this.pushEvent("restore_separator", { separator: saved })
    }

    // File upload handling
    const input = this.el.querySelector("input[type='file']")
    if (input) {
      input.addEventListener("change", (e) => {
        const file = e.target.files[0]
        if (!file) return

        const reader = new FileReader()
        reader.onload = (event) => {
          this.pushEvent("csv_file_selected", {
            content: event.target.result,
            filename: file.name,
          })
        }
        reader.readAsText(file)
      })
    }

    // Save separator to localStorage when it changes
    this.handleEvent("save_separator", ({ separator }) => {
      localStorage.setItem(STORAGE_KEY, separator)
    })
  },
}

export default CsvUpload
