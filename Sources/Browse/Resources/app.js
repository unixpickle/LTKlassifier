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
            const keyword = getQueryParam("keyword");
            const features = getQueryParam("features");
            if (id) {
                await this.loadNeighborGrid(id);
            } else if (keyword) {
                await this.loadKeywordGrid(keyword);
            } else if (features) {
                await this.loadFeaturesGrid(features);
            } else {
                await this.loadStartPage();
            }
            document.body.classList.remove('loading');
        } catch (e) {
            this.showError(e);
        }
    }

    async loadStartPage() {
        const response = await fetchJSON("/firstPage");
        const ids = response.ids;
        this.prices = response.prices;
        this.imageGrid.innerHTML = "";
        ids.forEach((id) => this.addImageToGrid(id));

        const keywordContainer = document.getElementById('keyword-list');
        KEYWORDS.forEach((keyword) => {
            const link = document.createElement('a');
            link.classList.add('keyword-item');
            link.href = `?keyword=${encodeURIComponent(keyword)}`;
            link.textContent = keyword;
            keywordContainer.appendChild(link);
        });

        const imageUpload = document.getElementById('image-upload');
        imageUpload.addEventListener('click', () => this.uploadFile());

        document.body.classList.add('start-page');
    }

    async loadNeighborGrid(id) {
        const response = await fetchJSON(`/neighbors?id=${id}`);
        this.neighbors = response.neighbors;
        this.prices = response.prices;

        await this.createProductHeading(id);
        this.createVarietyDropdown();

        const defaultLevel = Object.keys(this.neighbors)[0];
        this.updateNeighborGrid(defaultLevel);

        document.body.classList.add('product-page');
    }

    async loadKeywordGrid(keyword) {
        const response = await fetchJSON(`/neighbors?keyword=${encodeURIComponent(keyword)}`);
        this.neighbors = response.neighbors;
        this.prices = response.prices;

        document.getElementById('keyword-heading-label').textContent = keyword;
        this.createVarietyDropdown();

        const defaultLevel = Object.keys(this.neighbors)[0];
        this.updateNeighborGrid(defaultLevel);

        document.body.classList.add('keyword-page');
    }

    async loadFeaturesGrid(features) {
        const response = await fetchJSON(`/neighbors?features=${encodeURIComponent(features)}`);
        this.neighbors = response.neighbors;
        this.prices = response.prices;

        this.createVarietyDropdown();

        const defaultLevel = Object.keys(this.neighbors)[0];
        this.updateNeighborGrid(defaultLevel);

        document.body.classList.add('features-page');
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

    showError(err) {
        document.body.className = 'fatal-error';
        document.getElementById('error-message').textContent = '' + err;
    }

    createVarietyDropdown() {
        document.querySelectorAll(".variety-button").forEach((button) => {
            button.addEventListener("click", () => {
                document.querySelectorAll(".variety-button").forEach((btn) => {
                    btn.classList.remove("selected")
                });
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

    uploadFile() {
        const input = document.getElementById('image-upload-input');
        input.onchange = async (e) => {
            const file = e.target.files[0];
            if (!file) {
                return;
            }

            try {
                document.body.className = 'loading';
                let encoded = await shrinkAndEncodeImage(file);
                const response = await fetch('/encode', {
                    method: 'POST',
                    headers: { 'Content-Type': 'image/jpeg' },
                    body: encoded
                });

                if (!response.ok) {
                    this.showError('Failed to upload image.');
                    return;
                }

                const featureData = await response.text();
                window.location = `?features=${encodeURIComponent(featureData)}`
            } catch (error) {
                this.showError(`Failed to read uploaded file: ${error}`);
            }
        };
        input.click();
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

function shrinkAndEncodeImage(file) {
    const maxSize = 224;
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => {
            // Calculate new dimensions while maintaining aspect ratio
            var width = img.width;
            var height = img.height;
            let scale = maxSize / Math.max(width, height);
            width = Math.round(width * scale);
            height = Math.round(height * scale);

            // Draw the resized image on a canvas
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0, width, height);

            // Convert canvas to JPEG
            canvas.toBlob(blob => {
                resolve(blob);
            }, 'image/jpeg', 0.9);
        };
        img.onerror = reject;
        img.src = URL.createObjectURL(file);
    });
}

document.addEventListener("DOMContentLoaded", async () => {
    window.app = new App();
    window.app.loadGrid();
});

const KEYWORDS = [
    "women's",
    "men's",
    "dress",
    "bodycon",
    "bag",
    "top",
    "earrings",
    "necklace",
    "bracelet",
    "ring",
    "leather",
    "shoes",
    "boots",
    "heel",
    "jacket",
    "puffer",
    "jeans",
    "pants",
    "skirt",
    "pillow",
    "cardigan",
    "kids",
    "sunglasses",
    "socks",
    "rug",
    "sneakers",
    "blazer",
    "bra",
    "tumbler",
]
