class App {
    constructor() {
        this.imageGrid = document.getElementById("image-grid");
        this.productHeading = document.getElementById("product-heading");
        this.homeLink = document.getElementById("home-link");
        this.neighbors = null;
    }

    async loadGrid() {
        const id = getQueryParam("id");

        if (id) {
            this.neighbors = await fetchJSON(`/neighbors?id=${id}`);
            this.createDetailDropdown();

            this.createProductHeading(id);

            const defaultLevel = Object.keys(this.neighbors)[0];
            this.updateNeighborGrid(defaultLevel);
        } else {
            // Load the first page of images
            const ids = await fetchJSON("/firstPage");
            this.imageGrid.innerHTML = "";
            ids.forEach((id) => this.addImageToGrid(id));
            this.homeLink.style.display = 'none';
        }
    }

    addImageToGrid(id) {
        const imageContainer = document.createElement("div");
        imageContainer.classList.add("image-container");

        const zoomLink = document.createElement("a");
        zoomLink.href = `?id=${id}`;
        zoomLink.className = 'zoom-link';

        const img = document.createElement("img");
        img.src = `/productImage?id=${id}&preview=1`;
        img.dataset.id = id;
        zoomLink.append(img);

        const link = document.createElement("a");
        link.href = `/productRedirect?id=${id}`;
        link.classList.add("image-link");
        link.textContent = "🔗"; // You can replace this with an icon or text
        link.target = "_blank"; // Opens in a new tab
        link.rel = "noopener noreferrer"; // Security best practice

        imageContainer.appendChild(zoomLink);
        imageContainer.appendChild(link);
        this.imageGrid.appendChild(imageContainer);
    }

    createDetailDropdown() {
        document.getElementById('detail-container').style.display = '';
        document.querySelectorAll(".detail-button").forEach(button => {
            button.addEventListener("click", () => {
                document.querySelectorAll(".detail-button").forEach(btn => btn.classList.remove("selected"));
                button.classList.add("selected");

                const level = button.getAttribute("data-level");
                this.updateNeighborGrid(level);
            });
        });
    }

    async createProductHeading(id) {
        const img = this.productHeading.getElementsByClassName('image')[0];
        img.src = `/productImage?id=${id}`;

        const title = this.productHeading.getElementsByClassName('title')[0];
        title.href = `/productRedirect?id=${id}`;
        title.innerText = 'Unknown product name';

        this.productHeading.style = '';
        let name = await (await fetch(`/productName?id=${id}`)).text();
        title.innerText = name;
    }

    updateNeighborGrid(level) {
        this.imageGrid.innerHTML = "";
        this.neighbors[level].forEach((id) => this.addImageToGrid(id));
    }
}

async function fetchJSON(url) {
    const response = await fetch(url);
    return response.json();
}

function getQueryParam(name) {
    const params = new URLSearchParams(window.location.search);
    return params.get(name);
}

document.addEventListener("DOMContentLoaded", async () => {
    window.app = new App();
    window.app.loadGrid();
});
