class App {
    constructor() {
        this.imageGrid = document.getElementById("image-grid");
        this.productHeading = document.getElementById("product-heading");
        this.homeLink = document.getElementById("home-link");
        this.neighbors = null;
        this.prices = {};
    }

    async loadGrid() {
        try {
            const id = getQueryParam("id");
            if (id) {
                await this.loadNeighborGrid(id);
            } else {
                await this.loadFirstPage();
            }
            document.body.classList.remove('loading');
        } catch (e) {
            document.body.classList.add('fatal-error');
            document.getElementById('error-message').textContent = '' + e;
        }
    }

    async loadFirstPage() {
        const response = await fetchJSON("/firstPage");
        const ids = response.ids;
        this.prices = response.prices;
        this.imageGrid.innerHTML = "";
        ids.forEach((id) => this.addImageToGrid(id));
    }

    async loadNeighborGrid(id) {
        const response = await fetchJSON(`/neighbors?id=${id}`);
        this.neighbors = response.neighbors;
        this.prices = response.prices;

        await this.createProductHeading(id);
        this.createDetailDropdown();

        const defaultLevel = Object.keys(this.neighbors)[0];
        this.updateNeighborGrid(defaultLevel);

        document.body.classList.add('product-page');
    }

    addImageToGrid(id) {
        const imageContainer = document.createElement("div");
        imageContainer.classList.add("image-container");

        const outerLink = document.createElement("a");
        outerLink.href = `?id=${id}`;
        outerLink.className = 'product-page-link';

        const img = document.createElement("img");
        img.src = `/productImage?id=${id}&preview=1`;
        img.dataset.id = id;
        outerLink.append(img);

        imageContainer.appendChild(outerLink);

        if (this.prices[id]) {
            const price = document.createElement("div");
            price.classList.add('product-price-blurb');
            price.textContent = "$" + Math.round(this.prices[id]);
            imageContainer.appendChild(price);
        }

        this.imageGrid.appendChild(imageContainer);
    }

    createDetailDropdown() {
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
        let info = await fetchJSON(`/productInfo?id=${id}`);

        const img = this.productHeading.getElementsByClassName('image')[0];
        img.src = `/productImage?id=${id}`;

        const title = this.productHeading.getElementsByClassName('product-name')[0];
        title.href = `/productRedirect?id=${id}`;
        title.innerText = info.name || 'Unknown product name';

        if (info.retailer) {
            const container = document.getElementsByClassName('field-retailer')[0];
            container.style.display = '';
            let value = container.getElementsByClassName('field-value')[0];
            value.textContent = info.retailer;
        }

        if (info.price) {
            const container = document.getElementsByClassName('field-price')[0];
            container.style.display = '';
            let value = container.getElementsByClassName('field-value')[0];
            value.textContent = '$' + info.price.toFixed(2);
        }

        this.productHeading.style = '';
    }

    updateNeighborGrid(level) {
        this.imageGrid.innerHTML = "";
        this.neighbors[level].forEach((id) => this.addImageToGrid(id));
    }
}

async function fetchJSON(url) {
    const response = await fetch(url);
    if (response.status == 403) {
        throw 'Permission denied. Perhaps the rate limit was exceeded?';
    }
    return response.json();
}

function getQueryParam(name) {
    const params = new URLSearchParams(window.location.search);
    return params.get(name);
}

function scrollToTop() {
    document.body.scrollTop = document.documentElement.scrollTop = 0;
}

document.addEventListener("DOMContentLoaded", async () => {
    window.app = new App();
    window.app.loadGrid();
});
